import { ChevronDown, ChevronUp, Trash2 } from "lucide-react";
import type { CommandLogEntry } from "../../../shared/types";

interface Props {
  entries: CommandLogEntry[];
  expanded: boolean;
  onExpandedChange: (expanded: boolean) => void;
  onClear: () => void;
}

export function Console({ entries, expanded, onExpandedChange, onClear }: Props): JSX.Element {
  const ToggleIcon = expanded ? ChevronDown : ChevronUp;

  return (
    <section className={expanded ? "consoleDrawer expanded" : "consoleDrawer"} aria-label="Console">
      <button className="consoleToggle" type="button" onClick={() => onExpandedChange(!expanded)} aria-expanded={expanded}>
        <div>
          <h2>Console</h2>
          <p>{entries.length} event(s)</p>
        </div>
        <ToggleIcon size={18} />
      </button>
      {expanded && (
        <div className="consoleBody">
          <div className="consoleActions">
            <button className="iconButton" onClick={onClear} title="Clear console">
              <Trash2 size={16} />
            </button>
          </div>
          <pre className="consoleOutput">
            {entries.length === 0
              ? "No command output yet."
              : entries.map((entry) => `[${entry.stream}] ${entry.message}`).join("").trimEnd()}
          </pre>
        </div>
      )}
    </section>
  );
}
