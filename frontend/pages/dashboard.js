import { useState, useEffect } from 'react';
import { useRouter } from 'next/router';
import Layout from '../components/Layout';
import MessagesTable from '../components/MessagesTable';
import ContactsTable from '../components/ContactsTable';
import UsersTable from '../components/UsersTable';

export default function Dashboard({ user, onLogout }) {
  const [activeTab, setActiveTab] = useState('messages');
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  useEffect(() => {
    // Redirect to login if not authenticated
    if (!user) {
      router.replace('/login');
      return;
    }
    setLoading(false);
  }, [user, router]);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="loading-spinner w-8 h-8"></div>
        <span className="ml-3 text-gray-600">Loading dashboard...</span>
      </div>
    );
  }

  const tabs = [
    { id: 'messages', name: 'Messages', component: <MessagesTable /> },
    { id: 'contacts', name: 'Contacts', component: <ContactsTable /> },
  ];

  // Add users tab only for admin users
  if (user?.role === 'admin') {
    tabs.push({ id: 'users', name: 'Users', component: <UsersTable /> });
  }

  return (
    <Layout user={user} onLogout={onLogout}>
      <div className="px-4 py-6 sm:px-0">
        {/* Tab Navigation */}
        <div className="border-b border-gray-200">
          <nav className="-mb-px flex space-x-8">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm ${
                  activeTab === tab.id
                    ? 'border-blue-500 text-blue-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                {tab.name}
              </button>
            ))}
          </nav>
        </div>

        {/* Tab Content */}
        <div className="mt-6">
          {tabs.find(tab => tab.id === activeTab)?.component}
        </div>
      </div>
    </Layout>
  );
}