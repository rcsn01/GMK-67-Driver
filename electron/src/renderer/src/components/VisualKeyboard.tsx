import { visualKeyboardRows } from "../lib/keyboard";

interface Props {
  colorsByKey: Map<string, string>;
  selectedKey?: string;
  mappingsByKey?: Map<string, string>;
  sourceKey?: string | null;
  onSelect?: (key: string) => void;
}

export function VisualKeyboard({ selectedKey = "", colorsByKey, mappingsByKey, sourceKey, onSelect }: Props): JSX.Element {
  return (
    <div className="keyboard" aria-label="GMK67 visual keyboard">
      {visualKeyboardRows.map((row, rowIndex) => (
        <div className="keyboardRow" key={rowIndex}>
          {row.map((item) => {
            if (item.kind === "spacer") {
              return <span className="keyboardSpacer" key={`spacer-${rowIndex}-${item.width}`} style={{ width: item.width }} aria-hidden="true" />;
            }

            const color = colorsByKey.get(item.spec.toLowerCase());
            const mapping = mappingsByKey?.get(item.spec.toLowerCase());
            const isSelected = selectedKey.toLowerCase() === item.spec.toLowerCase();
            const isSource = sourceKey?.toLowerCase() === item.spec.toLowerCase();
            return (
              <button
                key={item.spec}
                className={`keyButton ${isSelected ? "selected" : ""} ${mapping ? "remapped" : ""} ${isSource ? "fnSource" : ""} ${onSelect ? "" : "readOnly"}`}
                style={{ width: item.width, background: color ? `#${color}` : undefined }}
                onClick={onSelect ? () => onSelect(item.spec) : undefined}
                title={mapping ? `${item.spec} -> ${mapping}` : item.spec}
              >
                <span>{item.label}</span>
                {mapping && <small>{mapping}</small>}
              </button>
            );
          })}
        </div>
      ))}
    </div>
  );
}
