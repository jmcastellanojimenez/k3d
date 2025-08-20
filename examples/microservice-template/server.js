const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const compression = require('compression');
const morgan = require('morgan');
const pino = require('pino');
const promApiMetrics = require('prometheus-api-metrics');
require('dotenv').config();

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  transport: {
    target: 'pino-pretty',
    options: {
      colorize: true
    }
  }
});

const app = express();
const port = process.env.PORT || 3000;
const serviceName = process.env.SERVICE_NAME || 'ecotrack-service';

// Middleware
app.use(helmet());
app.use(cors());
app.use(compression());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));
app.use(morgan('combined', { stream: { write: message => logger.info(message.trim()) } }));

// Prometheus metrics
app.use(promApiMetrics());

// Request ID middleware
app.use((req, res, next) => {
  req.id = req.get('X-Request-ID') || Math.random().toString(36).substr(2, 9);
  res.set('X-Request-ID', req.id);
  next();
});

// Logging middleware
app.use((req, res, next) => {
  logger.info({
    requestId: req.id,
    method: req.method,
    url: req.url,
    userAgent: req.get('User-Agent')
  }, 'Incoming request');
  next();
});

// Health checks
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    service: serviceName,
    timestamp: new Date().toISOString(),
    version: process.env.npm_package_version || '1.0.0'
  });
});

app.get('/ready', (req, res) => {
  // Add readiness checks here (database connectivity, etc.)
  res.status(200).json({
    status: 'ready',
    service: serviceName,
    timestamp: new Date().toISOString()
  });
});

app.get('/metrics', (req, res) => {
  // Prometheus metrics endpoint is handled by promApiMetrics middleware
  res.end();
});

// Main API routes
app.get('/api/v1/status', (req, res) => {
  logger.info({ requestId: req.id }, 'Status endpoint called');
  res.json({
    service: serviceName,
    version: '1.0.0',
    environment: process.env.NODE_ENV || 'development',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    pid: process.pid
  });
});

// Sample CRUD operations
app.get('/api/v1/items', async (req, res) => {
  try {
    logger.info({ requestId: req.id }, 'Fetching items');
    // Implement your data fetching logic here
    const items = [
      { id: 1, name: 'Carbon Footprint', value: 125.5, unit: 'kg CO2' },
      { id: 2, name: 'Energy Usage', value: 450.2, unit: 'kWh' },
      { id: 3, name: 'Water Consumption', value: 1250, unit: 'liters' }
    ];
    
    res.json({
      success: true,
      data: items,
      count: items.length,
      requestId: req.id
    });
  } catch (error) {
    logger.error({ requestId: req.id, error: error.message }, 'Error fetching items');
    res.status(500).json({
      success: false,
      error: 'Internal server error',
      requestId: req.id
    });
  }
});

app.post('/api/v1/items', async (req, res) => {
  try {
    logger.info({ requestId: req.id, body: req.body }, 'Creating new item');
    
    // Validate request body
    if (!req.body.name || !req.body.value || !req.body.unit) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: name, value, unit',
        requestId: req.id
      });
    }

    // Implement your data creation logic here
    const newItem = {
      id: Math.floor(Math.random() * 1000),
      name: req.body.name,
      value: req.body.value,
      unit: req.body.unit,
      created: new Date().toISOString()
    };

    res.status(201).json({
      success: true,
      data: newItem,
      requestId: req.id
    });
  } catch (error) {
    logger.error({ requestId: req.id, error: error.message }, 'Error creating item');
    res.status(500).json({
      success: false,
      error: 'Internal server error',
      requestId: req.id
    });
  }
});

// Error handling middleware
app.use((err, req, res, next) => {
  logger.error({
    requestId: req.id,
    error: err.message,
    stack: err.stack
  }, 'Unhandled error');

  res.status(err.status || 500).json({
    success: false,
    error: process.env.NODE_ENV === 'production' ? 'Internal server error' : err.message,
    requestId: req.id
  });
});

// 404 handler
app.use('*', (req, res) => {
  logger.warn({ requestId: req.id, url: req.originalUrl }, 'Route not found');
  res.status(404).json({
    success: false,
    error: 'Route not found',
    requestId: req.id
  });
});

// Graceful shutdown
process.on('SIGINT', () => {
  logger.info('SIGINT received. Shutting down gracefully...');
  process.exit(0);
});

process.on('SIGTERM', () => {
  logger.info('SIGTERM received. Shutting down gracefully...');
  process.exit(0);
});

// Start server
app.listen(port, '0.0.0.0', () => {
  logger.info(`${serviceName} listening on port ${port}`);
  logger.info(`Health check: http://localhost:${port}/health`);
  logger.info(`Ready check: http://localhost:${port}/ready`);
  logger.info(`API status: http://localhost:${port}/api/v1/status`);
});

module.exports = app;