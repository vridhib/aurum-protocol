/**
 * Stat card section to assemble a stats grid.
 * @param title Stat title.
 * @param value Stat value correlating to `title`. 
 * @returns Stat card UI component displaying a single statistic (shown as a title and value).
 */
export function StatCard({ title, value }: { title: string; value: string }) {
  return (
    <div className="bg-gray-800 border border-gray-700 p-6 rounded-xl shadow-sm">
      <h3 className="text-gray-400 font-medium">{title}</h3>
      <p className="text-2xl font-mono text-white mt-2">{value}</p>
    </div>
  );
}