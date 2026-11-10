
const request = require("supertest");
const createApp = require("../src/app");

const config = {
  port: 3000,
  logLevel: "info",
  environment: "test",
  version: "1.0.0"
};

const silentLogger = {
  debug: jest.fn(),
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn()
};

describe("DevOps Task Service API", () => {
  let app;

  beforeEach(() => {
    app = createApp(config, silentLogger);
  });

  // GET /
  describe("GET /", () => {
    test("should return the expected welcome message", async () => {
      const response = await request(app).get("/");

      expect(response.status).toBe(200);

      expect(response.body).toEqual({
        message: "Hello from DevOps Task!",
        status: "running",
        version: "1.0.0"
      });
    });

    test("should return JSON content type", async () => {
      const response = await request(app).get("/");

      expect(response.headers["content-type"])
        .toMatch(/application\/json/);
    });

    test("should use the configured application version", async () => {
      const customApp = createApp({
        ...config,
        version: "2.5.0"
      }, silentLogger);

      const response = await request(customApp).get("/");

      expect(response.body.version).toBe("2.5.0");
    });
  });

  // GET /health
  describe("GET /health", () => {
    test("should return healthy status", async () => {
      const response = await request(app).get("/health");

      expect(response.status).toBe(200);
      expect(response.body.status).toBe("healthy");
    });

    test("should report liveness and readiness checks", async () => {
      const response = await request(app).get("/health");

      expect(response.body.checks).toEqual({
        liveness: "ok",
        readiness: "ok"
      });
    });

    test("should report the configured environment", async () => {
      const response = await request(app).get("/health");

      expect(response.body.environment).toBe("test");
    });

    test("should return process uptime", async () => {
      const response = await request(app).get("/health");

      expect(typeof response.body.uptime).toBe("number");
      expect(response.body.uptime).toBeGreaterThan(0);
    });
  });

  // GET /metrics
  describe("GET /metrics", () => {
    test("should return Prometheus metrics", async () => {
      const response = await request(app).get("/metrics");

      expect(response.status).toBe(200);

      expect(response.headers["content-type"])
        .toContain("text/plain");

      expect(response.text).toContain("http_requests_total");
      expect(response.text).toContain("http_errors_total");
      expect(response.text).toContain(
        "http_request_duration_seconds"
      );
    });

    test("should expose request counter", async () => {
      await request(app).get("/");
      await request(app).get("/");

      const response = await request(app).get("/metrics");

      expect(response.text).toContain("http_requests_total");
      expect(response.text).toMatch(
        /http_requests_total\{[^}]*status_code="200"[^}]*\} 2/
      );
    });

    test("should expose error counter for 404 responses", async () => {
      await request(app).get("/does-not-exist");

      const response = await request(app).get("/metrics");

      expect(response.text).toContain("http_errors_total");
      expect(response.text).toMatch(
        /http_errors_total\{[^}]*status_code="404"[^}]*\} 1/
      );
    });

    test("should record request latency histogram", async () => {
      await request(app).get("/");

      const response = await request(app).get("/metrics");

      expect(response.text).toContain(
        "http_request_duration_seconds_bucket"
      );

      expect(response.text).toContain(
        'http_request_duration_seconds_count{'
      );
    });

    test("should not count metrics scraping requests", async () => {
      await request(app).get("/metrics");

      const response = await request(app).get("/metrics");

      expect(response.text).not.toContain("http_requests_total{");
    });
  });
});
