/**
 * Feature card used in the About page to assemble a features grid.
 * 
 * Renders a light-gold and bronze themed rectangular card for displaying 
 * a single feature with a title and corresponding description.
 * 
 * @component
 * @param {Object} props 
 * @param {Icon} props.icon The feature icon.
 * @param {string} props.title The feature title.
 * @param {string} props.description The feature description. 
 * @returns A feature card.
 */
export function FeatureCard({
    icon: Icon,
    title,
    description,
}: {
    icon: React.ElementType;
    title: string;
    description: string;
}) {
    return (
        <div className="gold-card p-6 hover:border-yellow-600/60 group">
            <Icon className="w-8 h-8 text-yellow-700 mb-3 group-hover:scale-110 transition-transform"/>
            <p className="text-lg font-semibold text-gray-900 mb-2">{title}</p>
            <p className="text-gray-700 text-sm leading-relaxed">{description}</p>
        </div>
    );
}