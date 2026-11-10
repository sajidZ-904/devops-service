
require("dotenv").config();

const validLogLevels = ["debug", "info", "warn", "error"];
const validEnvironments = [
  "development",
  "staging",
  "production"
];

function required(name) {
  const value = process.env[name];

  if (!value || !value.trim()) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value.trim();
}

const port = Number(required("PORT"));
const logLevel = required("LOG_LEVEL").toLowerCase();
const environment = required("ENVIRONMENT").toLowerCase();
const version = required("APP_VERSION");

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("PORT must be an integer between 1 and 65535");
}

if (!validLogLevels.includes(logLevel)) {
  throw new Error(
    `Invalid LOG_LEVEL. Allowed: ${validLogLevels.join(", ")}`
  );
}

if (!validEnvironments.includes(environment)) {
  throw new Error(
    `Invalid ENVIRONMENT. Allowed: ${validEnvironments.join(", ")}`
  );
}

module.exports = {
  port,
  logLevel,
  environment,
  version
};
