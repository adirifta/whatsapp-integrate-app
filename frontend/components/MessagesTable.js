import { useState, useEffect } from 'react';
import { whatsappAPI } from '../utils/api';

export default function MessagesTable() {
  const [messages, setMessages] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [pagination, setPagination] = useState({
    page: 1,
    limit: 20,
    total: 0,
    pages: 0
  });

  const fetchMessages = async (page = 1) => {
    try {
      setLoading(true);
      const response = await whatsappAPI.getMessages({
        page,
        limit: pagination.limit
      });
      
      setMessages(response.data.messages);
      setPagination(response.data.pagination);
      setError('');
    } catch (error) {
      console.error('Error fetching messages:', error);
      setError('Failed to load messages');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchMessages();
  }, []);

  const formatDate = (dateString) => {
    return new Date(dateString).toLocaleString();
  };

  const getMessageTypeBadge = (type) => {
    const typeMap = {
      text: 'badge-info',
      image: 'badge-success',
      video: 'badge-warning',
      document: 'badge-secondary',
      audio: 'badge-primary'
    };
    
    return typeMap[type] || 'badge-info';
  };

  const getStatusBadge = (status) => {
    const statusMap = {
      sent: 'badge-info',
      delivered: 'badge-success',
      read: 'badge-primary',
      error: 'badge-error'
    };
    
    return statusMap[status] || 'badge-info';
  };

  if (loading) {
    return (
      <div className="table-container p-6">
        <div className="flex justify-center items-center py-8">
          <div className="loading-spinner w-8 h-8"></div>
          <span className="ml-3 text-gray-600">Loading messages...</span>
        </div>
      </div>
    );
  }

  return (
    <div className="table-container">
      <div className="p-6 border-b border-gray-200">
        <div className="flex justify-between items-center">
          <h2 className="text-lg font-semibold text-gray-900">
            WhatsApp Messages
          </h2>
          <div className="flex items-center space-x-2">
            <span className="text-sm text-gray-600">
              Total: {pagination.total} messages
            </span>
            <button
              onClick={() => fetchMessages()}
              className="btn btn-outline text-sm"
            >
              Refresh
            </button>
          </div>
        </div>
      </div>

      {error && (
        <div className="p-4">
          <div className="alert alert-error">
            {error}
          </div>
        </div>
      )}

      <div className="table-responsive">
        <table className="table">
          <thead>
            <tr>
              <th>From</th>
              <th>To</th>
              <th>Message</th>
              <th>Type</th>
              <th>Status</th>
              <th>Timestamp</th>
            </tr>
          </thead>
          <tbody>
            {messages.length === 0 ? (
              <tr>
                <td colSpan="6" className="text-center py-8 text-gray-500">
                  No messages found
                </td>
              </tr>
            ) : (
              messages.map((message) => (
                <tr key={message.id}>
                  <td>
                    <div>
                      <div className="font-medium text-gray-900">
                        {message.contact_name || message.from_number}
                      </div>
                      <div className="text-xs text-gray-500">
                        {message.from_number}
                      </div>
                    </div>
                  </td>
                  <td className="text-sm text-gray-900">
                    {message.to_number}
                  </td>
                  <td>
                    <div className="max-w-xs">
                      <div className="text-sm text-gray-900 truncate">
                        {message.message || '(No text)'}
                      </div>
                      {message.message && message.message.length > 50 && (
                        <div 
                          className="text-xs text-gray-500 mt-1 cursor-pointer"
                          title={message.message}
                        >
                          {message.message.substring(0, 50)}...
                        </div>
                      )}
                    </div>
                  </td>
                  <td>
                    <span className={`badge ${getMessageTypeBadge(message.message_type)}`}>
                      {message.message_type}
                    </span>
                  </td>
                  <td>
                    <span className={`badge ${getStatusBadge(message.status)}`}>
                      {message.status}
                    </span>
                  </td>
                  <td className="text-sm text-gray-500">
                    {formatDate(message.timestamp)}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {pagination.pages > 1 && (
        <div className="p-4 border-t border-gray-200">
          <div className="flex justify-between items-center">
            <div className="text-sm text-gray-600">
              Page {pagination.page} of {pagination.pages}
            </div>
            <div className="flex space-x-2">
              <button
                onClick={() => fetchMessages(pagination.page - 1)}
                disabled={pagination.page === 1}
                className="btn btn-outline text-sm"
              >
                Previous
              </button>
              <button
                onClick={() => fetchMessages(pagination.page + 1)}
                disabled={pagination.page === pagination.pages}
                className="btn btn-outline text-sm"
              >
                Next
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}