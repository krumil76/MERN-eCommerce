import express from 'express';
import path from 'path';
import cookieParser from 'cookie-parser';
import cors from 'cors';
import compression from 'compression';
import 'dotenv/config';

import productRoutes from './routes/productRoutes.js';
import userRoutes from './routes/userRoutes.js';
import orderRoutes from './routes/orderRoutes.js';
import uploadRoutes from './routes/uploadRoutes.js';
import paymentRoutes from './routes/paymentRoutes.js';

import connectDB from './config/db.js';
import { notFound, errorHandler } from './middleware/errorMiddleware.js';

const port = process.env.PORT || 5000;
const app = express();
const __dirname = path.join(process.cwd(), 'backend');

// Connect to MongoDB
connectDB();

// Middleware
app.use(cors());
app.use(compression());
app.use(cookieParser());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Health check for ALB
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'ok',
    service: 'ecommerce-backend'
  });
});

// Backend root endpoint
app.get('/', (req, res) => {
  res.status(200).json({
    message: 'Ecommerce backend API is running',
    health: '/health',
    products: '/api/v1/products'
  });
});

// Uploaded files
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// API routes
app.use('/api/v1/products', productRoutes);
app.use('/api/v1/users', userRoutes);
app.use('/api/v1/orders', orderRoutes);
app.use('/api/v1/upload', uploadRoutes);
app.use('/api/v1/payment', paymentRoutes);

// Error handling
app.use(notFound);
app.use(errorHandler);

// Start server
app.listen(port, '0.0.0.0', () => {
  console.log(`Ecommerce backend running on port ${port}`);
});
