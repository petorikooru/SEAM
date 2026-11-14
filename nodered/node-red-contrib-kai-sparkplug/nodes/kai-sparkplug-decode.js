'use strict';

const path = require('path');
const protobuf = require('protobufjs');

module.exports = function register(RED) {
    const protoPath = path.join(__dirname, '..', 'proto', 'sparkplug_b.proto');
    const root = protobuf.loadSync(protoPath);
    const Payload = root.lookupType('org.eclipse.tahu.protobuf.Payload');

    const FALLBACK_ALIASES = new Map([
        [1, 'ACC/TEMPERATURE'], [2, 'ACC/ROLL'], [3, 'ACC/PITCH'],
        [4, 'VAR/DOUBLE'], [5, 'VAR/STRING'], [16, 'ACC/X'],
        [17, 'ACC/Y'], [18, 'ACC/Z']
    ]);
    const COMMAND_TYPES = new Set(['NCMD', 'DCMD']);
    const BIRTH_TYPES = new Set(['NBIRTH', 'DBIRTH']);
    const DEATH_TYPES = new Set(['NDEATH', 'DDEATH']);
    const NODE_TYPES = new Set(['NBIRTH', 'NDEATH', 'NDATA', 'NCMD']);
    const DEVICE_TYPES = new Set(['DBIRTH', 'DDEATH', 'DDATA', 'DCMD']);

    function KaiSparkplugDecodeNode(config) {
        RED.nodes.createNode(this, config);
        const node = this;
        node.namespace = String(config.namespace || 'spBv1.0');
        node.aliases = new Map();
        node.sequences = new Map();
        node.status({fill: 'grey', shape: 'ring', text: 'waiting'});

        node.on('input', function onInput(msg, send, done) {
            try {
                const topic = parseTopic(String(msg.topic || ''), node.namespace);
                if (topic.messageType === 'STATE') {
                    send(stateEnvelope(topic, msg.payload));
                    node.status({fill: 'green', shape: 'dot', text: 'STATE'});
                    done();
                    return;
                }
                if (COMMAND_TYPES.has(topic.messageType)) {
                    node.status({fill: 'blue', shape: 'ring', text: 'command ignored'});
                    done();
                    return;
                }
                const bytes = Buffer.isBuffer(msg.payload) ? msg.payload : Buffer.from(msg.payload || []);
                if (bytes.length === 0) {
                    done();
                    return;
                }
                const decoded = Payload.decode(bytes);
                const payload = Payload.toObject(decoded, {
                    longs: String,
                    enums: Number,
                    bytes: Buffer,
                    defaults: false,
                    oneofs: true
                });
                const entityKey = aliasKeyOf(topic);
                if (topic.messageType === 'NBIRTH') {
                    clearEdgeAliases(node.aliases, topic);
                }
                if (BIRTH_TYPES.has(topic.messageType)) {
                    node.aliases.set(entityKey, new Map());
                }
                const aliasMap = node.aliases.get(entityKey) || new Map();
                node.aliases.set(entityKey, aliasMap);
                const sequence = optionalNumber(payload.seq);
                const sequenceValid = updateSequence(
                    node.sequences,
                    sequenceKeyOf(topic),
                    sequence,
                    topic.messageType === 'NBIRTH'
                );
                const points = [];

                if (DEATH_TYPES.has(topic.messageType)) {
                    points.push(point(topic, 'ONLINE', false, payload.timestamp, null, sequence));
                } else {
                    if (BIRTH_TYPES.has(topic.messageType)) {
                        points.push(point(topic, 'ONLINE', true, payload.timestamp, null, sequence));
                    }
                    for (const metric of payload.metrics || []) {
                        const alias = optionalNumber(metric.alias);
                        let name = metric.name ? String(metric.name).toUpperCase() : '';
                        if (name && alias !== null) aliasMap.set(alias, name);
                        if (!name && alias !== null) name = aliasMap.get(alias) || FALLBACK_ALIASES.get(alias) || '';
                        if (!name || metric.isNull || metric.is_null) continue;
                        points.push(...metricPoints(topic, metric, name, payload.timestamp, sequence));
                    }
                }
                if (!sequenceValid) {
                    node.warn(`Sparkplug sequence discontinuity on ${topic.groupId}/${topic.edgeNodeId}`);
                    points.push(point(topic, 'SPARKPLUG_SEQUENCE_VALID', false, payload.timestamp, null, sequence));
                }
                if (points.length === 0) {
                    done();
                    return;
                }
                msg.payload = {
                    schema: 'kai.telemetry.v1',
                    source_topic: msg.topic,
                    group_id: topic.groupId,
                    edge_node_id: topic.edgeNodeId,
                    sparkplug_device_id: topic.deviceId || null,
                    device_id: topic.deviceId || topic.edgeNodeId,
                    sequence,
                    points
                };
                msg.sparkplug = topic;
                node.status({fill: 'green', shape: 'dot', text: `${topic.messageType}: ${points.length} point(s)`});
                send(msg);
                done();
            } catch (error) {
                node.status({fill: 'red', shape: 'ring', text: error.message});
                done(error);
            }
        });
    }

    RED.nodes.registerType('kai-sparkplug-decode', KaiSparkplugDecodeNode);

    function parseTopic(topic, namespace) {
        const parts = topic.split('/');
        if (parts[0] !== namespace) throw new Error(`Expected namespace ${namespace}`);
        if (parts.length === 3 && parts[1] === 'STATE') {
            return {namespace, groupId: '', messageType: 'STATE', edgeNodeId: parts[2], deviceId: null};
        }
        if (parts.length < 4 || parts.length > 5) throw new Error(`Invalid Sparkplug topic: ${topic}`);
        const messageType = parts[2].toUpperCase();
        const deviceId = parts.length === 5 ? parts[4] : null;
        if (!NODE_TYPES.has(messageType) && !DEVICE_TYPES.has(messageType)) {
            throw new Error(`Unsupported Sparkplug message type: ${messageType}`);
        }
        if (DEVICE_TYPES.has(messageType) && !deviceId) {
            throw new Error(`Device topic requires device id: ${topic}`);
        }
        if (NODE_TYPES.has(messageType) && deviceId) {
            throw new Error(`Node topic must not include device id: ${topic}`);
        }
        return {namespace, groupId: parts[1], messageType, edgeNodeId: parts[3], deviceId};
    }

    function aliasKeyOf(topic) {
        return [topic.groupId, topic.edgeNodeId, topic.deviceId || ''].join('/');
    }

    function sequenceKeyOf(topic) {
        return [topic.groupId, topic.edgeNodeId].join('/');
    }

    function clearEdgeAliases(aliasState, topic) {
        const prefix = `${topic.groupId}/${topic.edgeNodeId}/`;
        for (const key of aliasState.keys()) {
            if (key.startsWith(prefix)) aliasState.delete(key);
        }
    }

    function stateEnvelope(topic, raw) {
        const value = Buffer.isBuffer(raw) ? raw.toString('utf8').trim() : String(raw || '').trim();
        if (!['ONLINE', 'OFFLINE'].includes(value)) throw new Error(`Invalid STATE payload: ${value}`);
        return {
            topic: `${topic.namespace}/STATE/${topic.edgeNodeId}`,
            payload: {
                schema: 'kai.telemetry.v1',
                device_id: topic.edgeNodeId,
                points: [{
                    device_id: topic.edgeNodeId,
                    metric_name: 'STATE',
                    value,
                    timestamp_ns: nowNs(),
                    quality: 'good'
                }]
            }
        };
    }

    function updateSequence(state, key, sequence, reset) {
        if (sequence === null) return true;
        const previous = state.get(key);
        state.set(key, sequence);
        if (reset || previous === undefined) return true;
        return sequence === ((previous + 1) % 256);
    }

    function metricPoints(topic, metric, name, payloadTimestamp, sequence) {
        const fallbackNs = sparkplugTimestampNs(metric.timestamp || payloadTimestamp);
        const dataset = metric.datasetValue || metric.dataset_value;
        if (dataset) return datasetPoints(topic, metric, name, dataset, fallbackNs, sequence);
        const value = scalarValue(metric);
        if (value === undefined || (typeof value === 'number' && !Number.isFinite(value))) return [];
        return [point(topic, name, value, fallbackNs, optionalNumber(metric.alias), sequence, true)];
    }

    function datasetPoints(topic, metric, name, dataset, fallbackNs, sequence) {
        const columns = dataset.columns || [];
        const rows = (dataset.rows || []).map(row => (row.elements || []).map(scalarValue));
        const alias = optionalNumber(metric.alias);
        const result = [];
        if (['ACC/X', 'ACC/Y', 'ACC/Z'].includes(name)) {
            const intervalNs = inferInterval(rows);
            for (const row of rows) {
                if (row.length < 2) continue;
                const rowNs = microsecondsToNs(row[0], fallbackNs);
                for (let i = 1; i < row.length; i += 1) {
                    if (isScalar(row[i])) result.push(point(topic, name, row[i], addNs(rowNs, (i - 1) * intervalNs), alias, sequence, true));
                }
            }
            return result;
        }
        if (['ACC/PITCH', 'ACC/ROLL', 'ACC/TEMPERATURE'].includes(name)) {
            for (const row of rows) {
                if (!row.length || !isScalar(row[0])) continue;
                result.push(point(topic, name, row[0], row.length > 1 ? microsecondsToNs(row[1], fallbackNs) : fallbackNs, alias, sequence, true));
            }
            return result;
        }
        if (['VAR/DOUBLE', 'VAR/STRING'].includes(name)) {
            for (const row of rows) {
                let rowNs = fallbackNs;
                const deferred = [];
                for (let i = 0; i < columns.length && i < row.length; i += 1) {
                    const column = String(columns[i]).toUpperCase();
                    if (column === 'TIMESTAMP') rowNs = microsecondsToNs(row[i], fallbackNs);
                    else if (isScalar(row[i])) deferred.push([canonicalMetric(column), row[i]]);
                }
                for (const [metricName, value] of deferred) result.push(point(topic, metricName, value, rowNs, alias, sequence, true));
            }
            return result;
        }
        rows.forEach((row, rowIndex) => row.forEach((value, columnIndex) => {
            if (!isScalar(value)) return;
            const column = columns[columnIndex] || `column_${columnIndex}`;
            const p = point(topic, `${name}/${column}`, value, fallbackNs, alias, sequence, true);
            p.tags = {dataset_row: String(rowIndex)};
            result.push(p);
        }));
        return result;
    }

    function point(topic, metricName, value, timestamp, alias, sequence, alreadyNs = false) {
        return {
            device_id: topic.deviceId || topic.edgeNodeId,
            metric_name: metricName,
            value,
            timestamp_ns: alreadyNs ? timestamp : sparkplugTimestampNs(timestamp),
            quality: 'good',
            group_id: topic.groupId || null,
            edge_node_id: topic.edgeNodeId,
            sparkplug_device_id: topic.deviceId || null,
            alias,
            sequence
        };
    }

    function scalarValue(valueContainer) {
        if (valueContainer === null || valueContainer === undefined) return undefined;
        const candidates = ['intValue', 'int_value', 'longValue', 'long_value', 'floatValue', 'float_value', 'doubleValue', 'double_value', 'booleanValue', 'boolean_value', 'stringValue', 'string_value'];
        for (const key of candidates) {
            if (Object.prototype.hasOwnProperty.call(valueContainer, key)) {
                const value = valueContainer[key];
                if (key.toLowerCase().includes('long')) return numberOrString(value);
                return value;
            }
        }
        return undefined;
    }

    function numberOrString(value) {
        if (typeof value === 'number') return value;
        const numeric = Number(value);
        return Number.isSafeInteger(numeric) ? numeric : String(value);
    }

    function optionalNumber(value) {
        if (value === undefined || value === null || value === '') return null;
        const numeric = Number(value);
        return Number.isFinite(numeric) ? numeric : null;
    }

    function sparkplugTimestampNs(value) {
        const integer = positiveBigInt(value);
        return integer === null ? nowNs() : (integer * 1000000n).toString();
    }

    function microsecondsToNs(value, fallback) {
        const integer = positiveBigInt(value);
        if (integer === null) return fallback;
        if (integer > 1000000000000n) return (integer * 1000n).toString();
        if (integer > 1000000000n) return (integer * 1000000000n).toString();
        return (integer * 1000n).toString();
    }

    function positiveBigInt(value) {
        if (value === undefined || value === null || value === '') return null;
        const text = String(value).trim();
        if (!/^\d+$/.test(text)) return null;
        try {
            const result = BigInt(text);
            return result > 0n ? result : null;
        } catch (_error) {
            return null;
        }
    }

    function nowNs() {
        return (BigInt(Date.now()) * 1000000n).toString();
    }

    function addNs(timestampNs, offsetNs) {
        const base = positiveBigInt(timestampNs);
        if (base === null) return nowNs();
        return (base + BigInt(Math.max(0, Math.trunc(offsetNs)))).toString();
    }

    function inferInterval(rows) {
        if (rows.length < 2 || rows[0].length < 2 || rows[1].length === 0) return 4000000;
        const first = Number(rows[0][0]);
        const second = Number(rows[1][0]);
        const samples = rows[0].length - 1;
        if (!Number.isFinite(first) || !Number.isFinite(second) || samples <= 0 || second <= first) return 4000000;
        return Math.max(1, Math.trunc(((second - first) * 1000) / samples));
    }

    function isScalar(value) {
        return value !== undefined && value !== null && (typeof value !== 'number' || Number.isFinite(value));
    }

    function canonicalMetric(name) {
        return ({BAT_FUEL_GAUGE_REPSOC: 'BATTERY', SIGNAL: 'CELLULAR_RSSI', RSSI: 'CELLULAR_RSSI'})[name] || name;
    }
};
