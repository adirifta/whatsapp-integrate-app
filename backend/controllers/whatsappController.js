import pool from '../config/database.js';
import whatsappService from '../services/whatsappService.js';

export const getMessages = async (req, res) => {
  try {
    const { page = 1, limit = 50 } = req.query;
    const offset = (page - 1) * limit;

    const connection = await pool.getConnection();
    const [rows] = await connection.execute(`
      SELECT wm.*, wc.name as contact_name 
      FROM whatsapp_messages wm 
      LEFT JOIN whatsapp_contacts wc ON wm.from_number = wc.number 
      ORDER BY wm.timestamp DESC
      LIMIT ? OFFSET ?
    `, [parseInt(limit), offset]);
    
    const [countResult] = await connection.execute(
      'SELECT COUNT(*) as total FROM whatsapp_messages'
    );
    
    connection.release();
    
    res.json({
      messages: rows,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: countResult[0].total,
        pages: Math.ceil(countResult[0].total / limit)
      }
    });
  } catch (error) {
    console.error('Get messages error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

export const getContacts = async (req, res) => {
  try {
    const { page = 1, limit = 50 } = req.query;
    const offset = (page - 1) * limit;

    const connection = await pool.getConnection();
    const [rows] = await connection.execute(`
      SELECT * FROM whatsapp_contacts 
      ORDER BY name, number
      LIMIT ? OFFSET ?
    `, [parseInt(limit), offset]);
    
    const [countResult] = await connection.execute(
      'SELECT COUNT(*) as total FROM whatsapp_contacts'
    );
    
    connection.release();
    
    res.json({
      contacts: rows,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: countResult[0].total,
        pages: Math.ceil(countResult[0].total / limit)
      }
    });
  } catch (error) {
    console.error('Get contacts error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

export const getWhatsAppStatus = async (req, res) => {
  try {
    const status = await whatsappService.getStatus();
    res.json(status);
  } catch (error) {
    console.error('Get WhatsApp status error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

export const getQRCode = async (req, res) => {
  try {
    const qrCode = whatsappService.getQRCode();
    if (qrCode) {
      res.json({ qrCode });
    } else {
      const status = await whatsappService.getStatus();
      if (status.isReady) {
        res.json({ message: 'WhatsApp is already connected' });
      } else {
        res.status(404).json({ error: 'QR code not available' });
      }
    }
  } catch (error) {
    console.error('Get QR code error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

export const restartWhatsApp = async (req, res) => {
  try {
    await whatsappService.destroy();
    setTimeout(async () => {
      await whatsappService.initialize();
    }, 2000);
    
    res.json({ message: 'WhatsApp client restart initiated' });
  } catch (error) {
    console.error('Restart WhatsApp error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};