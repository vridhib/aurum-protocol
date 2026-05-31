import { ExternalLink } from "lucide-react";


/**
 * Link card used in the About page to assemble a links grid.
 * 
 * Renders a light-gold and bronze themed rectangular card for displaying 
 * a single link with a title, corresponding description, and embedded
 * link.
 * 
 * @component
 * @param {Object} props 
 * @param {string} props.title The link title.
 * @param {string} props.description The link description. 
 * @param {string} props.href The embedded link. 
 * @returns A link card.
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