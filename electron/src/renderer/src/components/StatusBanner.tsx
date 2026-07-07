import { AlertTriangle, RefreshCw, ShieldAlert, Usb } from "lucide-react";
import type { ReadinessReport } from "../../../shared/types";

interface Props {
  readiness: ReadinessReport | null;
  loading: boolean;
  onRefresh: () => void;
  onPermission: () => void;
}

function statusText(readiness: ReadinessReport | null): { title: string; detail: string; tone: string } {
  if (!readiness) {
    return { title: "Checking keyboard", detail: "USB and permission status have not been loaded.", tone: "checking" };
  }
  if (readiness.status === "ready") {
    return { title: "Keyboard ready", detail: "USB, resources, encoders, and HID permission are available.", tone: "ready" };
  }
  if (!readiness.usbDeviceOK) {
    return { title: "Keyboard not detected", detail: "Connect the GMK67 by USB and refresh status.", tone: "blocked" };
  }
  if (readiness.hidOpenPermission === "failed") {
    return { title: "Permission needed", detail: "macOS is blocking HID access for this app/helper.", tone: "warning" };
  }
  return { title: "Partially ready", detail: readiness.warnings[0] ?? readiness.failures[0] ?? "Open the console for details.", tone: "warning" };
}

export function StatusBanner({ readiness, loading, onRefresh, onPermission }: Props): JSX.Element | null {
  if (readiness?.status === "ready" && readiness.warnings.length === 0 && readiness.failures.length === 0) {
    return null;
  }

  const status = statusText(readiness);
  const Icon = status.tone === "blocked" ? Usb : ShieldAlert;

  return (
    <section className={`statusBanner ${status.tone}`}>
      <div className="statusIcon">
        <Icon size={22} />
      </div>
      <div>
        <h2>{status.title}</h2>
        <p>{status.detail}</p>
      </div>
      <div className="statusFacts">
        <span>{readiness?.devices.length ?? 0} interface(s)</span>
        <span>{readiness?.mappedPhysicalRGBKeyCount ?? "-"} RGB keys</span>
      </div>
      <button className="iconButton" onClick={onPermission} title="Request Input Monitoring permission">
        <AlertTriangle size={17} />
      </button>
      <button className="primaryButton" onClick={onRefresh} disabled={loading}>
        <RefreshCw size={16} />
        Refresh
      </button>
    </section>
  );
}
