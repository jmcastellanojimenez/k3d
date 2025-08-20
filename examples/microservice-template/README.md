# EcoTrack Microservice Template

A production-ready Node.js microservice template for the EcoTrack platform, designed to run on Kubernetes with Istio service mesh.

## 🚀 Features

- **Express.js** - Fast, minimalist web framework
- **Security First** - Helmet.js, CORS, input validation
- **Observability** - Structured logging (Pino), Prometheus metrics, health checks
- **Service Mesh Ready** - Istio integration with traffic management
- **Container Optimized** - Multi-stage Docker builds, non-root user
- **Kubernetes Native** - Complete K8s manifests with security best practices
- **Testing** - Jest test suite with supertest
- **Production Ready** - Graceful shutdown, error handling, monitoring

## 📁 Project Structure

```
microservice-template/
├── server.js              # Main application server
├── healthcheck.js          # Docker health check script
├── package.json           # Node.js dependencies and scripts
├── Dockerfile             # Multi-stage container build
├── .env.example           # Environment variables template
├── tests/
│   └── service.test.js    # API tests
└── k8s/                   # Kubernetes manifests
    ├── deployment.yaml    # Application deployment
    ├── service.yaml       # Kubernetes service
    ├── configmap.yaml     # Configuration
    ├── secret.yaml        # Sensitive data
    ├── serviceaccount.yaml # RBAC configuration
    └── virtualservice.yaml # Istio traffic management
```

## 🛠️ Quick Start

### Local Development

1. **Clone and setup:**
   ```bash
   cp .env.example .env
   npm install
   ```

2. **Run development server:**
   ```bash
   npm run dev
   ```

3. **Run tests:**
   ```bash
   npm test
   npm run test:coverage
   ```

### Docker Development

1. **Build container:**
   ```bash
   npm run docker:build
   ```

2. **Run container:**
   ```bash
   npm run docker:run
   ```

### Kubernetes Deployment

1. **Apply manifests:**
   ```bash
   kubectl apply -f k8s/
   ```

2. **Port-forward for testing:**
   ```bash
   kubectl port-forward -n ecotrack-dev svc/ecotrack-service 3000:80
   ```

## 🔍 API Endpoints

### Health & Monitoring

- `GET /health` - Health check endpoint
- `GET /ready` - Readiness probe endpoint  
- `GET /metrics` - Prometheus metrics

### Core API

- `GET /api/v1/status` - Service status and info
- `GET /api/v1/items` - Get all items
- `POST /api/v1/items` - Create new item

### Example API Usage

```bash
# Check service status
curl http://localhost:3000/api/v1/status

# Get items
curl http://localhost:3000/api/v1/items

# Create item
curl -X POST http://localhost:3000/api/v1/items \
  -H "Content-Type: application/json" \
  -d '{"name": "Solar Panels", "value": 500.0, "unit": "kWh"}'
```

## ⚙️ Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure:

```bash
# Service
SERVICE_NAME=ecotrack-service
PORT=3000
NODE_ENV=production

# Database
DATABASE_URL=postgresql://user:pass@host:port/db
REDIS_URL=redis://host:port

# Kafka
KAFKA_BROKER=kafka:9092
KAFKA_GROUP_ID=ecotrack-group

# Security
JWT_SECRET=your-secret-key
API_KEY=your-api-key
```

### Kubernetes Configuration

Update the ConfigMap and Secret in `k8s/` directory:

- `configmap.yaml` - Non-sensitive configuration
- `secret.yaml` - Database credentials, API keys, secrets

## 🔒 Security Features

- **Non-root container** - Runs as user 1001
- **Read-only filesystem** - Prevents runtime modifications
- **Security headers** - Helmet.js middleware
- **Input validation** - Request body validation
- **RBAC** - Kubernetes role-based access control
- **Network policies** - Istio traffic management

## 📊 Monitoring & Observability

### Logging

Structured JSON logging with Pino:

```javascript
logger.info({ requestId: req.id, userId: 123 }, 'User action performed');
```

### Metrics

Prometheus metrics automatically exposed at `/metrics`:
- HTTP request duration
- Request count by status code  
- Node.js process metrics
- Custom business metrics

### Health Checks

- **Liveness**: `/health` - Is the service running?
- **Readiness**: `/ready` - Is the service ready to accept traffic?
- **Startup**: Health check with longer initial delay

### Tracing

Istio automatically instruments HTTP calls for distributed tracing with Jaeger.

## 🚦 Traffic Management

### Istio Configuration

The service includes Istio configuration for:

- **Circuit Breaking** - Prevent cascade failures
- **Retries** - Automatic retry with exponential backoff
- **Timeouts** - Request timeout limits
- **Load Balancing** - LEAST_CONN algorithm
- **Fault Injection** - Testing resilience

### Access Patterns

```yaml
# Route traffic: /api/v1/service/* -> /api/v1/*
# 10% of requests get 5s delay for testing
# 3 retries with 2s per-try timeout
```

## 🧪 Testing

### Unit Tests

```bash
npm test                 # Run tests
npm run test:watch      # Watch mode
npm run test:coverage   # Coverage report
```

### Integration Testing

The template includes API integration tests:
- Health endpoint validation
- CRUD operations testing
- Error handling verification
- Security header validation

### Load Testing

Use tools like `k6` or `artillery` for load testing:

```bash
# Example with k6
k6 run --vus 10 --duration 30s load-test.js
```

## 🚀 Deployment

### CI/CD Integration

The service works with the platform's GitHub Actions workflows:

1. **Validate** - Lint, test, security scan
2. **Build** - Container image creation
3. **Deploy** - Kubernetes deployment
4. **Monitor** - Health verification

### Scaling

Horizontal Pod Autoscaler example:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ecotrack-service-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ecotrack-service
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

## 🔧 Customization

### Adding New Endpoints

1. Add route handlers in `server.js`
2. Add corresponding tests in `tests/service.test.js`
3. Update API documentation

### Database Integration

Example PostgreSQL integration:

```javascript
const { Pool } = require('pg');
const pool = new Pool({
  connectionString: process.env.DATABASE_URL
});

app.get('/api/v1/data', async (req, res) => {
  const result = await pool.query('SELECT * FROM items');
  res.json(result.rows);
});
```

### Custom Metrics

Add business metrics:

```javascript
const promClient = require('prom-client');
const requestCounter = new promClient.Counter({
  name: 'ecotrack_business_operations_total',
  help: 'Total business operations',
  labelNames: ['operation_type']
});

// Increment metric
requestCounter.inc({ operation_type: 'carbon_calculation' });
```

## 📚 Best Practices

### Code Quality

- **ESLint** - Code linting and formatting
- **Error Handling** - Comprehensive error middleware
- **Input Validation** - Validate all inputs
- **Async/Await** - Modern async patterns

### Performance

- **Compression** - GZIP response compression
- **Connection Pooling** - Database connection reuse
- **Caching** - Redis for session/data caching
- **Resource Limits** - Memory and CPU constraints

### Reliability

- **Graceful Shutdown** - Handle SIGTERM/SIGINT
- **Circuit Breaking** - Istio fault tolerance
- **Retry Logic** - Automatic retries with backoff
- **Health Checks** - Multiple probe types

## 🤝 Contributing

1. Follow the existing code style
2. Add tests for new features
3. Update documentation
4. Ensure security best practices

## 📝 License

MIT License - See LICENSE file for details