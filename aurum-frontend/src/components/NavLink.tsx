import Link from "next/link";
import { usePathname } from "next/navigation";


/**
 * Navigation link that is highlighted when active.
 * 
 * Compares the current pathname to the target `href` and applies a different 
 * text color when the user is on that page. Used inside {@link NavBar} to 
 * avoid repeated conditional styling for each link.
 * 
 * @component
 * @param {Object} props 
 * @param {string} props.href Target path (e.g., "/about")
 * @param {React.ReactNode} props.children Link label
 * @returns A styled Next.js {@link Link} element.
 */
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