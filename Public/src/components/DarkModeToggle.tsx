import React, { useState, useEffect } from "react";

export const DarkModeToggle = () => {
  const [dark, setDark] = useState(false);
  useEffect(() => {
    document.body.classList.toggle("dark-mode", dark);
  }, [dark]);
  return (
    <button onClick={() => setDark(d => !d)} aria-label="Toggle dark mode">
      {dark ? "🌙 Dark" : "☀️ Light"}
    </button>
  );
};

// Add this to your global CSS:
// .dark-mode { background: #181818; color: #eee; }
