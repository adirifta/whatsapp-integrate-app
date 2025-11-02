import express from 'express';
import { 
  getMessages, 
  getContacts, 
  getWhatsAppStatus,
  getQRCode,
  restartWhatsApp
} from '../controllers/whatsappController.js';
import { authenticateToken } from '../middleware/auth.js';

const router = express.Router();

router.use(authenticateToken);

router.get('/messages', getMessages);
router.get('/contacts', getContacts);
router.get('/status', getWhatsAppStatus);
router.get('/qrcode', getQRCode);
router.post('/restart', restartWhatsApp);

export default router;