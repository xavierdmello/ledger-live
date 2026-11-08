import React, { useCallback, useState } from "react";
import { Platform } from "react-native";
import { useDispatch } from "~/context/hooks";
import { trace } from "@ledgerhq/logs";
import { Flex } from "@ledgerhq/native-ui";
import { Device } from "@ledgerhq/live-common/hw/actions/types";
import { Result } from "@ledgerhq/live-common/hw/actions/manager";
import DeviceActionModal from "~/components/DeviceActionModal";
import SelectDevice2 from "~/components/SelectDevice2";
import Button from "~/components/PreventDoubleClickButton";

import {
  setHasInstalledAnyApp,
  setHasOrderedNano,
  setLastConnectedDevice,
  setReadOnlyMode,
} from "~/actions/settings";
import { useManagerDeviceAction } from "~/hooks/deviceActions";
import { HOOKS_TRACKING_LOCATIONS } from "~/analytics/hooks/variables";

type Props = {
  onSuccess: (device?: Device) => void;
  keepReadOnlyMode?: boolean;
};

const ConnectDevice = ({ onSuccess, keepReadOnlyMode = false }: Props) => {
  const action = useManagerDeviceAction();
  const dispatch = useDispatch();
  const [device, setDevice] = useState<Device | undefined>();

  // Does not react to an header update request:
  // Keeping the header (back arrow and information button) from the onboarding.
  const requestToSetHeaderOptions = useCallback(() => undefined, []);

  const leaveReadOnlyMode = useCallback(() => {
    if (!keepReadOnlyMode) dispatch(setReadOnlyMode(false));
  }, [dispatch, keepReadOnlyMode]);

  const onSelectDevice = useCallback(
    (device: Device) => {
      const isUsbDevice = device.wired;
      trace({ type: "onboarding", message: "Selected device", data: { isUsbDevice } });
      dispatch(setLastConnectedDevice(device));
      leaveReadOnlyMode();
      dispatch(setHasOrderedNano(false));
      // iOS USB goes through the smart-card (CCID) interface of the app open on the device;
      // the dashboard has none, so the manager action (device info, app list) can't run.
      // The device answered over USB with an app open, which is all onboarding needs here.
      if (isUsbDevice && Platform.OS === "ios") {
        dispatch(setHasInstalledAnyApp(true));
        onSuccess(device);
        return;
      }
      setDevice(device);
    },
    [dispatch, leaveReadOnlyMode, onSuccess],
  );

  const onResult = useCallback(
    (info: Result) => {
      /** if list apps succeed we update settings with state of apps installed */
      if (info) {
        const hasAnyAppinstalled = !!(
          info.result &&
          info.result.installed &&
          info.result.installed.length > 0
        );

        dispatch(setHasInstalledAnyApp(hasAnyAppinstalled));
        setDevice(undefined);
        leaveReadOnlyMode();
        dispatch(setHasOrderedNano(false));
        onSuccess(device);
      }
    },
    [device, dispatch, leaveReadOnlyMode, onSuccess],
  );

  return (
    <>
      <Flex flex={1}>
        <SelectDevice2
          onSelect={onSelectDevice}
          stopBleScanning={!!device}
          requestToSetHeaderOptions={requestToSetHeaderOptions}
          isChoiceDrawerDisplayedOnAddDevice={false}
          keepReadOnlyMode={keepReadOnlyMode}
        />
      </Flex>
      {device ? (
        <DeviceActionModal
          onClose={() => setDevice(undefined)}
          device={device}
          onResult={onResult}
          action={action}
          request={null}
          location={HOOKS_TRACKING_LOCATIONS.onboardingFlow}
        />
      ) : null}
      {__DEV__ ? (
        <Button
          mt={7}
          type="color"
          outline
          onPress={() => {
            leaveReadOnlyMode();
            dispatch(setHasOrderedNano(false));
            onSuccess();
          }}
        >
          (DEV) SKIP THIS STEP
        </Button>
      ) : null}
    </>
  );
};

export default ConnectDevice;
