import React, { useEffect } from "react";

export const Toast = ({ message, onClose }: { message: string, onClose: () => void }) => {
  useEffect(() => {
    const timer = setTimeout(onClose, 3000);
    return () => clearTimeout(timer);
  }, [onClose]);
  return (
    <div style={{
      position: "fixed",
      bottom: 24,
      right: 24,
      background: "#323232",
      color: "#fff",
      padding: "1em 2em",
      borderRadius: 8,
      boxShadow: "0 2px 8px rgba(0,0,0,0.15)",
      zIndex: 1000
    }}>
      {message}
    </div>
  );
};
