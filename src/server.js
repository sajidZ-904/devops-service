const config = require("./config");
const logger = require("./logger");
const createApp = require("./app");

const app = createApp(config, logger);

app.listen(config.port, "0.0.0.0", () => {
  logger.info("Application started", {
    port: config.port,
    version: config.version
  });
});
