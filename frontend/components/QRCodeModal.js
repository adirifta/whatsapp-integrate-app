import { useState, useEffect } from 'react';
import QRCode from 'qrcode';
import { whatsappAPI } from '../utils/api';

export default function QRCodeModal({ onClose, onRefresh }) {
  const [qrCode, setQrCode] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const fetchQRCode = async () => {
    try {
      setLoading(true);
      const response = await whatsappAPI.getQRCode();
      
      if (response.data.qrCode) {
        const qrImage = await QRCode.toDataURL(response.data.qrCode, {
          width: 256,
          margin: 2,
          color: {
            dark: '#000000',
            light: '#FFFFFF'
          }
        });
        setQrCode(qrImage);
        setError('');
      } else if (response.data.message) {
        setError(response.data.message);
      }
    } catch (error) {
      console.error('Error fetching QR code:', error);
      setError('Failed to load QR code');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchQRCode();
    const interval = setInterval(fetchQRCode, 5000); // Refresh every 5 seconds
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="modal-overlay">
      <div className="modal-content">
        <div className="modal-header">
          <div className="flex items-center justify-between">
            <h3 className="modal-title">Scan WhatsApp QR Code</h3>
            <button
              onClick={onClose}
              className="text-gray-400 hover:text-gray-600 text-xl"
            >
              ×
            </button>
          </div>
        </div>

        <div className="modal-body">
          {error && (
            <div className="alert alert-warning text-center">
              {error}
            </div>
          )}

          {loading && (
            <div className="flex justify-center items-center py-12">
              <div className="loading-spinner w-8 h-8"></div>
              <span className="ml-3 text-gray-600">Loading QR Code...</span>
            </div>
          )}

          {qrCode && !loading && (
            <div className="text-center">
              <div className="mb-4">
                <p className="text-sm text-gray-600 mb-2">
                  Scan this QR code with your WhatsApp mobile app to connect:
                </p>
                <ol className="text-sm text-gray-600 text-left list-decimal list-inside space-y-1 max-w-md mx-auto">
                  <li>Open WhatsApp on your phone</li>
                  <li>Tap Menu → Linked Devices</li>
                  <li>Tap Link a Device</li>
                  <li>Point your phone at this screen to scan the code</li>
                </ol>
              </div>
              
              <div className="flex justify-center mb-4">
                <img 
                  src={qrCode} 
                  alt="WhatsApp QR Code" 
                  className="border border-gray-200 rounded-lg"
                />
              </div>

              <div className="flex justify-center space-x-2">
                <button
                  onClick={fetchQRCode}
                  className="btn btn-outline text-sm"
                >
                  Refresh QR
                </button>
                <button
                  onClick={onRefresh}
                  className="btn btn-primary text-sm"
                >
                  Check Status
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}