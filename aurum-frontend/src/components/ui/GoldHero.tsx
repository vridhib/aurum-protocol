import { ArrowRight } from "lucide-react";
import { useRouter } from "next/navigation";


interface GoldHeroProps {
  title: string;
  subtitle: string;
  buttonText?: string;
  buttonHref?: string;
  showButton?: boolean;
  showBackgroundImage?: boolean;
}

/**
 * Gold-themed hero banner used across the Aurum frontend. 
 * 
 * Renders a gold gradient block with an optional gold‑bars background image,
 * a title, a subtitle, and an optional navigation button. Used on pages like
 * About, Savings, Faucet, and Gold Ledger for consistent branding.
 * 
 * @component
 * @param {Object} props 
 * @param {string} props.title The page title. 
 * @param {string} props.subtitle The page subtitle.
 * @param {string} props.buttonText Button lable (default: "Back to Dashboard").
 * @param {string} props.buttonHref Button navigation target (default: "/").
 * @param {boolean} props.showButton Whether to render the button (default: true).
 * @param {boolean} props.showBackgroundImage Whether to show the gold‑bars background image (default: false).
 * @returns A full-width hero banner.
 */
export function GoldHero({
  title,
  subtitle,
  buttonText = "Back to Dashboard",
  buttonHref = "/",
  showButton = true,
  showBackgroundImage = true,
}: GoldHeroProps) {
  const router = useRouter();

  return (
    <div>
      <div className="relative bg-gradient-to-b from-yellow-600/20 via-yellow-800/10 to-transparent rounded-2xl p-8 md:p-12 border border-yellow-700/30 overflow-hidden">
        {showBackgroundImage && (
          <div
            className="absolute inset-0 bg-cover bg-center opacity-15"
            style={{ backgroundImage: `url(/gold-bars.jpg)` }}
          />
        )}
        <div className="relative z-10 text-center">
          <h1 className="text-4xl md:text-6xl font-bold bg-gradient-to-r from-yellow-700 to-amber-800 bg-clip-text text-transparent drop-shadow-[0_0_10px_rgba(234,179,8,0.3)]">{title}</h1>
          <p className="mt-6 text-gray-800 max-w-2xl mx-auto text-lg md:text-xl leading-relaxed">
            {subtitle}
          </p>
          {showButton && (
            <button
              onClick={() => router.push(buttonHref)}
              className="mt-8 inline-flex items-center gap-2 px-6 py-3 bg-yellow-800/20 border border-yellow-600/40 text-yellow-800 rounded-full hover:bg-yellow-600/30 hover:border-yellow-500 transition shadow-lg shadow-yellow-900/10"
            >
              <ArrowRight className="w-4 h-4" />
              {buttonText}
            </button>
          )}
        </div>
      </div>

      {showBackgroundImage && <div className="mt-1">
        <p className="text-xs text-gray-500">
          Photo by {" "}
          <a
            href="https://unsplash.com/@scottsdalemint?utm_source=unsplash&utm_medium=referral&utm_content=creditCopyText"
            className="underline hover:text-yellow-700"
          >
            Scottsdale Mint
          </a>{" "}
          on{" "}
          <a
            href="https://unsplash.com/photos/a-pile-of-gold-bars-sitting-on-top-of-a-table--6BtUqTvWiE?utm_source=unsplash&utm_medium=referral&utm_content=creditCopyText"
            className="underline hover:text-yellow-700"
          >
            Unsplash
          </a>
        </p>
      </div>}

      <div className="gold-border mt-6"></div>
    </div>
  );
}