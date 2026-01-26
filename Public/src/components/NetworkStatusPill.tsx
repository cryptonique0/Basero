import React from "react";

export const NetworkStatusPill = ({ status }: { status: string }) => (
  <span style={{
    padding: "0.25em 0.75em",
    borderRadius: "999px",
    background: status === "online" ? "#4caf50" : "#f44336",
    color: "white",
    fontWeight: 600,
    fontSize: "0.9em",
    marginLeft: "0.5em"
  }}>
    {status === "online" ? "Online" : "Offline"}
  </span>
);
