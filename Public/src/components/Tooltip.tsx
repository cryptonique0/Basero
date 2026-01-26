import React, { useState } from "react";

export const Tooltip = ({ children, text }: { children: React.ReactNode, text: string }) => {
  const [show, setShow] = useState(false);
  return (
    <span style={{ position: 'relative', display: 'inline-block' }}
      onMouseEnter={() => setShow(true)}
      onMouseLeave={() => setShow(false)}
      tabIndex={0}
      onFocus={() => setShow(true)}
      onBlur={() => setShow(false)}
      aria-label={text}
    >
      {children}
      {show && (
        <span style={{
          position: 'absolute',
          bottom: '120%',
          left: '50%',
          transform: 'translateX(-50%)',
          background: '#333',
          color: '#fff',
          padding: '4px 8px',
          borderRadius: 4,
          fontSize: 12,
          whiteSpace: 'nowrap',
          zIndex: 100
        }}>{text}</span>
      )}
    </span>
  );
};
