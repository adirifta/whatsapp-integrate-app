import { createRequire } from 'module';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import qrcode from 'qrcode-terminal';

const require = createRequire(import.meta.url);
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Import WhatsApp Web.js menggunakan require
const { Client } = require('whatsapp-web.js');

class WhatsAppService {
  constructor() {
    this.client = null;
    this.isInitialized = false;
    this.qrCode = null;
    this.isLoading = false;
    
    // Untuk menyimpan auth strategy
    this.authStrategy = null;
  }

  async initializeClient() {
    if (this.isLoading) return;
    
    this.isLoading = true;
    try {
      // Gunakan LocalAuth dari require
      const { LocalAuth } = require('whatsapp-web.js');
      
      this.client = new Client({
        puppeteer: {
          headless: true,
          args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-accelerated-2d-canvas',
            '--no-first-run',
            '--no-zygote',
            '--disable-gpu'
          ]
        },
        authStrategy: new LocalAuth({
          clientId: "whatsapp-dashboard-client",
          dataPath: join(__dirname, '..', 'whatsapp_auth')
        })
      });

      this.initializeEvents();
      await this.client.initialize();
      
    } catch (error) {
      console.error('Error initializing WhatsApp client:', error);
      this.isLoading = false;
      throw error;
    }
  }

  initializeEvents() {
    if (!this.client) return;

    this.client.on('qr', (qr) => {
      console.log('QR Code received, scan it!');
      this.qrCode = qr;
      qrcode.generate(qr, { small: true });
      
      // Juga simpan QR code ke file untuk akses mudah
      this.saveQRCodeToFile(qr);
    });

    this.client.on('ready', () => {
      console.log('WhatsApp Client is ready!');
      this.isInitialized = true;
      this.isLoading = false;
      this.qrCode = null;
    });

    this.client.on('authenticated', () => {
      console.log('WhatsApp Client authenticated!');
    });

    this.client.on('auth_failure', (error) => {
      console.error('Authentication failed:', error);
      this.isInitialized = false;
      this.isLoading = false;
    });

    this.client.on('disconnected', (reason) => {
      console.log('WhatsApp client disconnected:', reason);
      this.isInitialized = false;
      this.isLoading = false;
      // Reinitialize after disconnect
      setTimeout(() => {
        this.initialize();
      }, 5000);
    });

    this.client.on('message', async (message) => {
      try {
        await this.saveMessage(message);
        await this.saveContact(message);
      } catch (error) {
        console.error('Error processing message:', error);
      }
    });

    this.client.on('message_create', async (message) => {
      // Handle outgoing messages
      if (message.fromMe) {
        try {
          await this.saveMessage(message);
        } catch (error) {
          console.error('Error processing outgoing message:', error);
        }
      }
    });
  }

  saveQRCodeToFile(qr) {
    try {
      const fs = require('fs');
      const path = require('path');
      const qrFilePath = path.join(__dirname, '..', 'qrcode.txt');
      fs.writeFileSync(qrFilePath, qr);
      console.log('QR code saved to:', qrFilePath);
    } catch (error) {
      console.error('Error saving QR code to file:', error);
    }
  }

  async saveMessage(message) {
    let connection;
    try {
      // Dynamic import untuk menghindari circular dependency
      const { default: pool } = await import('../config/database.js');
      connection = await pool.getConnection();
      
      // Skip if message is from status broadcast
      if (message.from && message.from.includes('status@broadcast')) {
        return;
      }

      const messageData = {
        id: message.id?._serialized || message.id,
        from: message.from,
        to: message.to || message.from,
        body: message.body || '',
        type: message.type || 'text',
        timestamp: message.timestamp ? new Date(message.timestamp * 1000) : new Date(),
        status: 'delivered'
      };

      // For outgoing messages
      if (message.fromMe) {
        messageData.from = message.to;
        messageData.to = message.from;
        messageData.status = 'sent';
      }

      await connection.execute(
        `INSERT INTO whatsapp_messages 
         (message_id, from_number, to_number, message, message_type, timestamp, status) 
         VALUES (?, ?, ?, ?, ?, ?, ?) 
         ON DUPLICATE KEY UPDATE 
         message = VALUES(message), status = VALUES(status), timestamp = VALUES(timestamp)`,
        [
          messageData.id,
          messageData.from,
          messageData.to,
          messageData.body,
          messageData.type,
          messageData.timestamp,
          messageData.status
        ]
      );
      
    } catch (error) {
      console.error('Error saving message:', error);
    } finally {
      if (connection) {
        connection.release();
      }
    }
  }

  async saveContact(message) {
    let connection;
    try {
      const { default: pool } = await import('../config/database.js');
      connection = await pool.getConnection();
      const contact = await message.getContact();
      
      // Skip if contact is from status broadcast
      if (contact.id._serialized.includes('status@broadcast')) {
        return;
      }

      const contactData = {
        id: contact.id._serialized,
        name: contact.name || contact.pushname || contact.shortName || 'Unknown',
        number: contact.number,
        isBusiness: contact.isBusiness || false
      };

      await connection.execute(
        `INSERT INTO whatsapp_contacts (contact_id, name, number, is_business) 
         VALUES (?, ?, ?, ?) 
         ON DUPLICATE KEY UPDATE 
         name = VALUES(name), is_business = VALUES(is_business)`,
        [
          contactData.id,
          contactData.name,
          contactData.number,
          contactData.isBusiness
        ]
      );
      
    } catch (error) {
      console.error('Error saving contact:', error);
    } finally {
      if (connection) {
        connection.release();
      }
    }
  }

  async initialize() {
    if (this.isInitialized || this.isLoading) {
      console.log('WhatsApp client already initialized or initializing');
      return;
    }

    try {
      await this.initializeClient();
      console.log('WhatsApp client initialization started...');
    } catch (error) {
      console.error('Error initializing WhatsApp client:', error);
      this.isLoading = false;
      throw error;
    }
  }

  async getStatus() {
    return {
      isReady: this.isInitialized,
      isAuthenticated: this.client?.info ? true : false,
      isInitializing: this.isLoading,
      user: this.client?.info ? this.client.info.pushname : null,
      phone: this.client?.info ? this.client.info.wid.user : null,
      hasQRCode: !!this.qrCode
    };
  }

  getQRCode() {
    return this.qrCode;
  }

  getClient() {
    return this.client;
  }

  // Method to manually destroy client (for cleanup)
  async destroy() {
    try {
      if (this.client) {
        await this.client.destroy();
      }
      this.isInitialized = false;
      this.isLoading = false;
      this.client = null;
      console.log('WhatsApp client destroyed');
    } catch (error) {
      console.error('Error destroying WhatsApp client:', error);
    }
  }
}

// Create singleton instance
const whatsappService = new WhatsAppService();

export default whatsappService;