/**
 * Lightweight gold-themed page header used across the Aurum frontend. 
 * 
 * Renders a simple page header using a gold-bronze color scheme, with a title, subtitle
 * and gold border. Used on data viewing and user action pages that do not use the heavier
 * {@link GoldHero} component, such as the Monitor and Dashboard pages.
 * 
 * @component
 * @param {Object} props
 * @param {string} props.title The page title.
 * @param {string} props.subtitle Optional page subtitle. 
 * @returns A full-width page header.
 */
export function PageHeader({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <div className="space-y-2">
      <h1 className="text-4xl font-bold text-yellow-800 mt-6">{title}</h1>
      {subtitle && <p className="text-yellow-700/70 text-sm">{subtitle}</p>}
      <hr className="gold-border" />
    </div>
  );
}