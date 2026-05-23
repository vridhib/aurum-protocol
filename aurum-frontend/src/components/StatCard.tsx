/**
 * Stat card section to assemble a stats grid.
 * @param title Stat title.
 * @param value Stat value correlating to `title`. 
 * @returns Stat card UI component displaying a single statistic (shown as block with a title and value).
 */
export function StatCard({ title, value }: { title: string; value: string }) {
  return (
    <div className="gold-card p-4 text-center hover:border-yellow-600/50;">
      <p className="text-yellow-900 text-xs uppercase tracking-wider font-semibold">{title}</p>
      <p className="text-2xl font-bold text-yellow-800 mt-1">{value}</p>
    </div>
  );
}