import { useState, useEffect } from 'react';
import { whatsappAPI } from '../utils/api';
import QRCodeModal from './QRCodeModal';

export default function WhatsAppStatus() {
  const [status, setStatus] = useState({});
  const [loading, setLoading] = useState(true);
  const [showQRModal, setShowQRModal] = useState(false);

  const fetchStatus = async () => {
    try {
      const response = await whatsappAPI.getStatus();
      setStatus(response.data);
    } catch (error) {
      console.error('Error fetching WhatsApp status:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchStatus();
    const interval = setInterval(fetchStatus, 10000); // Update every 10 seconds
    return () => clearInterval(interval);
  }, []);

  const getStatusColor = () => {
    if (status.isReady) return 'badge-success';
    if (status.hasQRCode) return 'badge-warning';
    return 'badge-error';
  };

  const getStatusText = () => {
    if (status.isReady) return 'Connected';
    if (status.hasQRCode) return 'Scan QR Code';
    return 'Disconnected';
  };

  const handleRestart = async () => {
    try {
      await whatsappAPI.restart();
      setTimeout(fetchStatus, 2000);
    } catch (error) {
      console.error('Error restarting WhatsApp:', error);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center space-x-2">
        <div className="loading-spinner w-4 h-4"></div>
        <span className="text-sm text-gray-500">Loading...</span>
      </div>
    );
  }

  return (
    <>
      <div className="flex items-center space-x-3">
        <div className="flex items-center space-x-2">
          <div className={`w-2 h-2 rounded-full ${
            status.isReady ? 'bg-green-500' : 
            status.hasQRCode ? 'bg-yellow-500' : 'bg-red-500'
          }`}></div>
          <span className="text-sm text-gray-600">WhatsApp:</span>
          <span className={`badge ${getStatusColor()}`}>
            {getStatusText()}
          </span>
        </div>

        {status.hasQRCode && (
          <button
            onClick={() => setShowQRModal(true)}
            className="btn btn-warning text-xs"
          >
            Show QR
          </button>
        )}

        {!status.isReady && !status.hasQRCode && (
          <button
            onClick={handleRestart}
            className="btn btn-outline text-xs"
          >
            Reconnect
          </button>
        )}
      </div>

      {showQRModal && (
        <QRCodeModal 
          onClose={() => setShowQRModal(false)}
          onRefresh={fetchStatus}
        />
      )}
    </>
  );
}