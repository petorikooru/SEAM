"""Manual dependency construction for the desktop application."""

from __future__ import annotations

from dataclasses import dataclass

from kai_bridge_inspection.application.paths import ApplicationPaths
from kai_bridge_inspection.controllers.application_controller import ApplicationController
from kai_bridge_inspection.controllers.backend_controller import BackendController
from kai_bridge_inspection.controllers.daemon_controller import DaemonController
from kai_bridge_inspection.controllers.dashboard_controller import DashboardController
from kai_bridge_inspection.controllers.settings_controller import SettingsController
from kai_bridge_inspection.controllers.sparkplug_controller import SparkplugController
from kai_bridge_inspection.settings.repository import SettingsRepository


@dataclass(slots=True)
class DesktopServices:
    paths                   : ApplicationPaths
    settings_repository     : SettingsRepository
    application_controller  : ApplicationController
    daemon_controller       : DaemonController
    backend_controller      : BackendController
    settings_controller     : SettingsController
    dashboard_controller    : DashboardController
    sparkplug_controller    : SparkplugController


def bootstrap_desktop() -> DesktopServices:
    paths = ApplicationPaths.resolve()
    settings = SettingsRepository(paths.settings_db)
    daemon_controller = DaemonController(settings, paths.telemetry_db)
    return DesktopServices(
        paths=paths,
        settings_repository=settings,
        application_controller=ApplicationController(),
        daemon_controller=daemon_controller,
        backend_controller=BackendController(paths, settings, daemon_controller),
        settings_controller=SettingsController(settings),
        dashboard_controller=DashboardController(),
        sparkplug_controller=SparkplugController(daemon_controller),
    )
