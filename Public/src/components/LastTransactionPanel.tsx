import React from "react";

export const LastTransactionPanel = ({ tx }: { tx: { hash: string, status: string, time: string } | null }) => (
  <div style={{
    border: "1px solid #eee",
    borderRadius: 8,
    padding: 16,
    margin: "1em 0",
    background: "#fafbfc"
  }}>
    <h4>Last Transaction</h4>
    {tx ? (
      <div>
        <div><b>Hash:</b> {tx.hash}</div>
        <div><b>Status:</b> {tx.status}</div>
        <div><b>Time:</b> {tx.time}</div>
      </div>
    ) : (
      <div>No recent transaction.</div>
    )}
  </div>
);
