import React from "react";

export const UserAvatar = ({ name, src }: { name: string, src?: string }) => (
  <span title={name} style={{ display: 'inline-flex', alignItems: 'center' }}>
    {src ? (
      <img src={src} alt={name} style={{ width: 32, height: 32, borderRadius: '50%', marginRight: 8 }} />
    ) : (
      <span style={{
        width: 32,
        height: 32,
        borderRadius: '50%',
        background: '#bdbdbd',
        color: '#fff',
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        marginRight: 8,
        fontWeight: 700
      }}>{name[0]}</span>
    )}
    <span>{name}</span>
  </span>
);
