const request = require('supertest');
const app = require('../server');

describe('EcoTrack Service API', () => {
  
  describe('Health endpoints', () => {
    test('GET /health should return 200', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);
      
      expect(response.body).toHaveProperty('status', 'healthy');
      expect(response.body).toHaveProperty('service');
      expect(response.body).toHaveProperty('timestamp');
    });

    test('GET /ready should return 200', async () => {
      const response = await request(app)
        .get('/ready')
        .expect(200);
      
      expect(response.body).toHaveProperty('status', 'ready');
      expect(response.body).toHaveProperty('service');
    });
  });

  describe('API endpoints', () => {
    test('GET /api/v1/status should return service status', async () => {
      const response = await request(app)
        .get('/api/v1/status')
        .expect(200);
      
      expect(response.body).toHaveProperty('service');
      expect(response.body).toHaveProperty('version');
      expect(response.body).toHaveProperty('uptime');
      expect(response.body).toHaveProperty('memory');
    });

    test('GET /api/v1/items should return items list', async () => {
      const response = await request(app)
        .get('/api/v1/items')
        .expect(200);
      
      expect(response.body).toHaveProperty('success', true);
      expect(response.body).toHaveProperty('data');
      expect(response.body).toHaveProperty('count');
      expect(Array.isArray(response.body.data)).toBe(true);
    });

    test('POST /api/v1/items should create new item', async () => {
      const newItem = {
        name: 'Test Item',
        value: 100.5,
        unit: 'kg'
      };

      const response = await request(app)
        .post('/api/v1/items')
        .send(newItem)
        .expect(201);
      
      expect(response.body).toHaveProperty('success', true);
      expect(response.body).toHaveProperty('data');
      expect(response.body.data).toHaveProperty('name', newItem.name);
      expect(response.body.data).toHaveProperty('value', newItem.value);
      expect(response.body.data).toHaveProperty('unit', newItem.unit);
    });

    test('POST /api/v1/items should return 400 for invalid data', async () => {
      const invalidItem = {
        name: 'Test Item'
        // Missing required fields: value, unit
      };

      const response = await request(app)
        .post('/api/v1/items')
        .send(invalidItem)
        .expect(400);
      
      expect(response.body).toHaveProperty('success', false);
      expect(response.body).toHaveProperty('error');
    });
  });

  describe('Error handling', () => {
    test('Should return 404 for non-existent routes', async () => {
      const response = await request(app)
        .get('/non-existent-route')
        .expect(404);
      
      expect(response.body).toHaveProperty('success', false);
      expect(response.body).toHaveProperty('error', 'Route not found');
    });
  });

  describe('Headers and security', () => {
    test('Should include security headers', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);
      
      // Check for some security headers set by helmet
      expect(response.headers).toHaveProperty('x-content-type-options');
      expect(response.headers).toHaveProperty('x-frame-options');
    });

    test('Should include request ID in response', async () => {
      const response = await request(app)
        .get('/api/v1/status')
        .expect(200);
      
      expect(response.headers).toHaveProperty('x-request-id');
      expect(response.body).toHaveProperty('requestId');
    });
  });
});