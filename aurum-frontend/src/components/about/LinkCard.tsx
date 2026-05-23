import { ExternalLink } from "lucide-react";


/**
 * Link card section to assemble a link grid.
 * @param title Link title.
 * @param description Link description correlating to `title`. 
 * @param href Actual link that is embedded in the link card. 
 * @returns Link card UI component displaying a single link (shown as a block with an embedded link, title, and description).
 */
export function LinkCard({
  title,
  description,
  href
}: {
  title: string;
  description: string;
  href: string
}) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className="block gold-card p-4 hover:border-yellow-600 group"
    >
      <div className="flex items-start justify-between">
        <div>
          <p className="text-gray-900 font-semibold group-hover:text-yellow-700 transition">{title}</p>
          <p className="text-gray-600 text-sm mt-1">{description}</p>
        </div>
        <ExternalLink className="w-4 h-4 text-gray-400 group-hover:text-yellow-700 transition flex-shrink-0 mt-0.5" />
      </div>
    </a>
  );
}