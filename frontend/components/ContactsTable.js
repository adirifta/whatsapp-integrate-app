import { useState, useEffect } from 'react';
import { whatsappAPI } from '../utils/api';

export default function ContactsTable() {
  const [contacts, setContacts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const fetchContacts = async () => {
    try {
      setLoading(true);
      const response = await whatsappAPI.getContacts();
      setContacts(response.data);
      setError('');
    } catch (error) {
      console.error('Error fetching contacts:', error);
      setError('Failed to load contacts');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchContacts();
  }, []);

  const formatDate = (dateString) => {
    if (!dateString) return 'Never';
    return new Date(dateString).toLocaleString();
  };

  if (loading) {
    return (
      <div className="table-container p-6">
        <div className="flex justify-center items-center py-8">
          <div className="loading-spinner w-8 h-8"></div>
          <span className="ml-3 text-gray-600">Loading contacts...</span>
        </div>
      </div>
    );
  }

  return (
    <div className="table-container">
      <div className="p-6 border-b border-gray-200">
        <div className="flex justify-between items-center">
          <h2 className="text-lg font-semibold text-gray-900">
            WhatsApp Contacts
          </h2>
          <div className="flex items-center space-x-2">
            <span className="text-sm text-gray-600">
              Total: {contacts.length} contacts
            </span>
            <button
              onClick={fetchContacts}
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
              <th>Name</th>
              <th>Phone Number</th>
              <th>Business</th>
              <th>Last Seen</th>
              <th>Added</th>
            </tr>
          </thead>
          <tbody>
            {contacts.length === 0 ? (
              <tr>
                <td colSpan="5" className="text-center py-8 text-gray-500">
                  No contacts found
                </td>
              </tr>
            ) : (
              contacts.map((contact) => (
                <tr key={contact.id}>
                  <td>
                    <div className="font-medium text-gray-900">
                      {contact.name}
                    </div>
                  </td>
                  <td className="text-sm text-gray-900 font-mono">
                    {contact.number}
                  </td>
                  <td>
                    <span className={`badge ${
                      contact.is_business ? 'badge-success' : 'badge-info'
                    }`}>
                      {contact.is_business ? 'Yes' : 'No'}
                    </span>
                  </td>
                  <td className="text-sm text-gray-500">
                    {formatDate(contact.last_seen)}
                  </td>
                  <td className="text-sm text-gray-500">
                    {formatDate(contact.created_at)}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}