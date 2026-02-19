import type { InputHTMLAttributes } from "react";
import { cn } from "../../lib/cn";

interface SwitchProps extends Omit<InputHTMLAttributes<HTMLInputElement>, "type"> {
  label: string;
}

export function Switch({ className, label, ...props }: SwitchProps) {
  return (
    <label className={cn("switch-row", className)}>
      <span>{label}</span>
      <input type="checkbox" {...props} />
    </label>
  );
}
