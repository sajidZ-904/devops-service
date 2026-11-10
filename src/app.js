
const express = require("express");
const client = require("prom-client");

function createApp(config, logger = console) {
  const app = express();
  const register = new client.Registry();

  register.setDefaultLabels({
    application: "devops-task-service",
    environment: config.environment
  });

  client.collectDefaultMetrics({ register });

  const requestCounter = new client.Counter({
    name: "http_requests_total",
    help: "Total HTTP requests",
    labelNames: ["method", "route", "status_code"],
    registers: [register]
  });

  const errorCounter = new client.Counter({
    name: "http_errors_total",
    help: "Total HTTP error responses",
    labelNames: ["method", "route", "status_code"],
    registers: [register]
  });

  const requestDuration = new client.Histogram({
    name: "http_request_duration_seconds",
    help: "HTTP request duration in seconds",
    labelNames: ["method", "route", "status_code"],
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
    registers: [register]
  });

  // Prometheus request monitoring middleware
  app.use((req, res, next) => {
    if (req.path === "/metrics") {
      return next();
    }

    const start = process.hrtime.bigint();

    res.on("finish", () => {
      const duration =
        Number(process.hrtime.bigint() - start) / 1e9;

      const route = req.route?.path || "unmatched";

      const labels = {
        method: req.method,
        route,
        status_code: String(res.statusCode)
      };

      requestCounter.inc(labels);
      requestDuration.observe(labels, duration);

      if (res.statusCode >= 400) {
        errorCounter.inc(labels);
      }

      logger.debug?.("HTTP request completed", {
        method: req.method,
        route,
        statusCode: res.statusCode,
        durationSeconds: duration
      });
    });

    next();
  });

  // GET /
  app.get("/", (req, res) => {
    res.status(200).json({
      message: "Hello from DevOps Task!",
      status: "running",
      version: config.version
    });
  });

  // GET /health
  app.get("/health", (req, res) => {
    res.status(200).json({
      status: "healthy",
      checks: {
        liveness: "ok",
        readiness: "ok"
      },
      environment: config.environment,
      uptime: process.uptime()
    });
  });

  // GET /metrics
  app.get("/metrics", async (req, res) => {
    try {
      res.set("Content-Type", register.contentType);
      res.end(await register.metrics());
    } catch (error) {
      logger.error?.("Metrics collection failed", {
        error: error.message
      });

      res.status(500).send("Unable to collect metrics");
    }
  });

  return app;
}

module.exports = createApp;
