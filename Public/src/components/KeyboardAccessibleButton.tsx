import React from "react";

export const KeyboardAccessibleButton = ({ onClick, children, ...props }: React.ButtonHTMLAttributes<HTMLButtonElement>) => (
  <button
    onClick={onClick}
    tabIndex={0}
    onKeyDown={e => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        onClick && onClick(e as any);
      }
    }}
    {...props}
  >
    {children}
  </button>
);
