import type Transport from "@ledgerhq/hw-transport";
import { isDmkTransport } from "./dmkUtils";

/**
 * On iOS, USB Ledgers are reached as smart-card (CCID) readers. Only the app open on the
 * device exposes that interface; the dashboard doesn't. So over USB the host can't list,
 * install or open apps, read device info, run the genuine check or update firmware.
 * The iOS app turns this on at startup.
 */
let usbDashboardUnreachable = false;

export const setUsbDashboardUnreachable = (value: boolean): void => {
  usbDashboardUnreachable = value;
};

export const isUsbDashboardUnreachable = (): boolean => usbDashboardUnreachable;

/** True for a USB session that can't reach the dashboard (iOS over CCID). Bluetooth is unaffected. */
export const isUsbSessionWithoutDashboard = (transport: Transport): boolean => {
  if (!usbDashboardUnreachable || !isDmkTransport(transport)) return false;
  try {
    return transport.dmk.getConnectedDevice({ sessionId: transport.sessionId }).type === "USB";
  } catch {
    return false;
  }
};
