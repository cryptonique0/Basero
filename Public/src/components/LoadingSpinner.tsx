import React from "react";

export const LoadingSpinner = () => (
  <div role="status" aria-live="polite" style={{ display: 'inline-block', margin: 8 }}>
    <svg width="32" height="32" viewBox="0 0 50 50">
      <circle cx="25" cy="25" r="20" fill="none" stroke="#1976d2" strokeWidth="5" strokeDasharray="31.4 31.4" strokeLinecap="round">
        <animateTransform attributeName="transform" type="rotate" from="0 25 25" to="360 25 25" dur="1s" repeatCount="indefinite" />
      </circle>
    </svg>
    <span style={{ position: 'absolute', left: -9999 }}>Loading...</span>
  </div>
);
