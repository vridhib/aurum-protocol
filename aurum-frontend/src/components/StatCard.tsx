/**
 * Stat card used across the Aurum frontend to assemble a stats grid.
 * 
 * Renders a light-gold and bronze themed squarish card for displaying 
 * a single statistic with a title and corresponding value.
 * 
 * @component
 * @param {Object} props
 * @param {string} props.title The stat card title.
 * @param {string} props.value The stat card value.
 * @returns A stat card.
 */
export function StatCard({ title, value }: { title: string; value: string }) {
  return (
    <div className="gold-card p-4 text-center hover:border-yellow-600/50 flex flex-col h-full">
      <p className="text-yellow-900 text-xs uppercase tracking-wider font-semibold">{title}</p>
      <div className="flex-1 flex items-center justify-center mt-1">
        <p className="text-2xl font-bold text-yellow-800">{value}</p>
      </div>
    </div>
  );
}