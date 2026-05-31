import { useState } from "react";
import { createPortal } from "react-dom";


/**
 * Portal‑based tooltip component.
 *
 * Renders a tooltip that appears above the trigger element on hover.
 * The tooltip is rendered into `document.body` via `createPortal`,
 * preventing it from being clipped by any parent with `overflow-hidden`
 * or `overflow-x-auto`. Positioning is calculated from the trigger’s 
 * bounding client rect, so the tooltip always appears directly above 
 * the text.
 *
 * @component
 * @param {Object} props
 * @param {React.ReactNode} props.children The trigger element (text or icon).
 * @param {React.ReactNode} props.content The tooltip body to display.
 * @returns A portal tooltip.
 */
export function TooltipPortal({ children, content }: { children: React.ReactNode, content: React.ReactNode }) {
  const [visible, setVisible] = useState(false);
  const [pos, setPos] = useState({ top: 0, left: 0 });

  const handleMouseEnter = (e: React.MouseEvent<HTMLDivElement>) => {
    const rect = (e.target as HTMLElement).closest("span")?.getBoundingClientRect();
    if (rect) {
      setPos({ top: rect.top - 8, left: rect.left + rect.width / 2 });
      setVisible(true);
    }
  };

  const handleMouseLeave = () => setVisible(false);

  return (
    <>
      <span
        onMouseEnter={handleMouseEnter}
        onMouseLeave={handleMouseLeave}
        className="cursor-help border-b border-dotted border-yellow-800/30 inline-block"
      >
        {children}
      </span>
      {visible &&
        createPortal(
          <div
            className="fixed z-50"
            style={{
              top: pos.top,
              left: pos.left,
              transform: "translate(-50%, -100%)",
            }}
          >
            <div className="bg-gray-900 text-white text-xs rounded-lg px-3 py-2 shadow-xl border border-yellow-800/30 min-w-[200px]">
              {content}
              <div className="absolute top-full left-1/2 -translate-x-1/2 w-3 h-2 bg-gray-900 border-l border-b border-yellow-800/30 rotate-45 -mt-0.5" />
            </div>
          </div>,
          document.body
        )}
    </>
  );
}