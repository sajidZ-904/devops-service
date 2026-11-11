const config = require("./config");
const logger = require("./logger");
const createApp = require("./app");

const app = createApp(config, logger);

const server = app.listen(config.port, "0.0.0.0", () => {
  logger.info("Application started", {
    port: config.port,
    version: config.version
  });
});

function shutdown(signal) {
  logger.info("Shutdown requested", { signal });
  server.close((error) => {
    if (error) {
      logger.error("Graceful shutdown failed", { error: error.message });
      process.exitCode = 1;
    }
    process.exit();
  });
}

process.once("SIGTERM", () => shutdown("SIGTERM"));
process.once("SIGINT", () => shutdown("SIGINT"));
