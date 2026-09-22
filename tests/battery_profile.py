#!/usr/bin/env python3
"""Behavioral checks for battery-profile's power-source and hold events."""

import runpy
import unittest
from pathlib import Path
from unittest.mock import Mock


BatteryHold = runpy.run_path(
    str(Path(__file__).resolve().parents[1] / "modules/battery-profile.py")
)["BatteryHold"]


class BatteryHoldTests(unittest.TestCase):
    def test_manual_selection_survives_unrelated_power_events(self):
        acquire = Mock(side_effect=[17, 18])
        release = Mock()
        hold = BatteryHold(acquire, release)

        hold.update(True)
        hold.profile_released(17)
        hold.update(True)  # UPower changed a property other than OnBattery.
        self.assertEqual(acquire.call_count, 1)

        hold.update(False)
        hold.update(True)
        self.assertEqual(acquire.call_count, 2)
        release.assert_not_called()  # PPD already released the first hold.

    def test_daemon_restart_reacquires_on_battery(self):
        acquire = Mock(side_effect=[17, 18])
        hold = BatteryHold(acquire, Mock())

        hold.update(True)
        hold.profile_released(17)
        hold.daemon_restarted()
        hold.update(True)
        self.assertEqual(acquire.call_count, 2)

    def test_unrelated_release_keeps_current_hold(self):
        release = Mock()
        hold = BatteryHold(Mock(return_value=17), release)

        hold.update(True)
        hold.profile_released(99)
        hold.update(False)
        release.assert_called_once_with(17)


if __name__ == "__main__":
    unittest.main()
