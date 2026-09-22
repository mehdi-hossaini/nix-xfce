"""Hold power-saver on battery without overwriting the desktop/game profile."""

import signal


class BatteryHold:
    def __init__(self, acquire, release):
        self.acquire = acquire
        self.release = release
        self.cookie = None
        self.on_battery = None
        self.manual_selection = False

    def update(self, on_battery):
        if on_battery != self.on_battery:
            self.on_battery = on_battery
            self.manual_selection = False
        if on_battery and self.cookie is None and not self.manual_selection:
            self.cookie = self.acquire()
        elif not on_battery and self.cookie is not None:
            cookie, self.cookie = self.cookie, None
            self.release(cookie)

    def profile_released(self, cookie):
        if cookie == self.cookie:
            self.cookie = None
            self.manual_selection = True

    def daemon_restarted(self):
        self.cookie = None
        self.manual_selection = False


def main():
    from gi.repository import Gio, GLib

    flags = Gio.DBusProxyFlags.NONE
    power = Gio.DBusProxy.new_for_bus_sync(
        Gio.BusType.SYSTEM, flags, None, "org.freedesktop.UPower",
        "/org/freedesktop/UPower", "org.freedesktop.UPower", None,
    )
    profiles = Gio.DBusProxy.new_for_bus_sync(
        Gio.BusType.SYSTEM, flags, None, "org.freedesktop.UPower.PowerProfiles",
        "/org/freedesktop/UPower/PowerProfiles",
        "org.freedesktop.UPower.PowerProfiles", None,
    )

    def call(method, arguments):
        return profiles.call_sync(method, arguments, Gio.DBusCallFlags.NONE, 5000, None)

    hold = BatteryHold(
        lambda: call("HoldProfile", GLib.Variant("(sss)", (
            "power-saver", "Laptop running on battery", "nixos-battery-profile",
        ))).unpack()[0],
        lambda cookie: call("ReleaseProfile", GLib.Variant("(u)", (cookie,))),
    )
    loop = GLib.MainLoop()
    failed = False

    def reconcile(*_):
        nonlocal failed
        if not profiles.get_name_owner() or not power.get_name_owner():
            return
        battery = power.get_cached_property("OnBattery")
        if battery is not None:
            try:
                hold.update(battery.unpack())
            except GLib.Error as error:
                # Let systemd reconnect after a daemon/policy failure.
                print(f"Battery profile request failed: {error}", flush=True)
                failed = True
                loop.quit()

    def profiles_restarted(*_):
        hold.daemon_restarted()
        reconcile()

    def profile_released(_proxy, _sender, name, parameters):
        # Respect an explicit user profile selection until the next power
        # source change. PPD releases all holds when the user selects a profile.
        if name == "ProfileReleased":
            hold.profile_released(parameters.unpack()[0])

    power.connect("g-properties-changed", reconcile)
    power.connect("notify::g-name-owner", reconcile)
    profiles.connect("notify::g-name-owner", profiles_restarted)
    profiles.connect("g-signal", profile_released)
    for sig in (signal.SIGTERM, signal.SIGINT):
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, lambda: loop.quit())
    reconcile()
    try:
        if not failed:
            loop.run()
    finally:
        if profiles.get_name_owner():
            try:
                hold.update(False)
            except GLib.Error:
                pass  # D-Bus also releases the hold when this process exits.
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
