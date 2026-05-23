/**
 * Feature card section to assemble a feature grid.
 * @param icon Feature icon.
 * @param title Feature title.
 * @param description Feature description correlating to `title`. 
 * @returns Feature card UI component displaying a single feature (shown as a block with a title, description, and icon).
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