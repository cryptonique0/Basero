import React, { useState } from "react";

export const SettingsPanel = () => {
  const [open, setOpen] = useState(false);
  return (
    <div>
      <button onClick={() => setOpen(o => !o)} aria-expanded={open} aria-controls="settings-panel">
        ⚙️ Settings
      </button>
      {open && (
        <div id="settings-panel" style={{
          position: 'absolute',
          right: 16,
          top: 48,
          background: '#fff',
          border: '1px solid #ddd',
          borderRadius: 8,
          padding: 16,
          minWidth: 200,
          zIndex: 1000
        }}>
          <h4>Preferences</h4>
          <label>
            <input type="checkbox" /> Enable notifications
          </label>
          <br />
          <label>
            <input type="checkbox" /> Dark mode
          </label>
        </div>
      )}
    </div>
  );
};
