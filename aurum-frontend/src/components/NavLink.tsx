import Link from "next/link";
import { usePathname } from "next/navigation";

export function NavLink({ href, children }: { href: string, children: React.ReactNode }) {
  const pathname = usePathname();
  const isActive = pathname === href;

  return (
    <Link
      href={href}
      className={`text-sm transition ${
        isActive 
          ? "text-gray-500" 
          : "text-gray-800 hover:text-gray-500"
      }`}
    >
      {children}
    </Link>
  );
}