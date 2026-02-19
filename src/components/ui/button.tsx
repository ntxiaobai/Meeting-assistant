import type { ButtonHTMLAttributes } from "react";
import { cn } from "../../lib/cn";

type ButtonVariant = "default" | "secondary" | "danger";

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
}

const variantClass: Record<ButtonVariant, string> = {
  default: "btn btn-default",
  secondary: "btn btn-secondary",
  danger: "btn btn-danger",
};

export function Button({ className, variant = "default", ...props }: ButtonProps) {
  return <button className={cn(variantClass[variant], className)} {...props} />;
}
