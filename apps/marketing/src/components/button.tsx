import { cva, type VariantProps } from "class-variance-authority";
import Link from "next/link";
import { cn } from "@/lib/utils";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 rounded-xl px-6 py-3.5 text-[15px] font-semibold transition-colors duration-200 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brass focus-visible:ring-offset-2 focus-visible:ring-offset-ivory disabled:pointer-events-none disabled:opacity-50",
  {
    variants: {
      variant: {
        primary: "bg-brass text-white hover:bg-brass-deep shadow-[0_8px_24px_rgba(168,130,60,0.28)]",
        ghost: "bg-transparent text-ink border border-line hover:border-line-2 hover:bg-paper",
        "on-dark": "bg-ivory text-evergreen-3 hover:bg-white",
        "ghost-on-dark": "bg-transparent text-ivory border border-white/25 hover:border-white/50 hover:bg-white/5",
      },
    },
    defaultVariants: {
      variant: "primary",
    },
  }
);

interface ButtonProps
  extends React.ComponentProps<"button">,
    VariantProps<typeof buttonVariants> {
  href?: string;
}

export function Button({ className, variant, href, ...props }: ButtonProps) {
  if (href) {
    return (
      <Link href={href} className={cn(buttonVariants({ variant }), className)}>
        {props.children as React.ReactNode}
      </Link>
    );
  }
  return <button className={cn(buttonVariants({ variant }), className)} {...props} />;
}
