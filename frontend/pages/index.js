import { useEffect } from 'react';
import { useRouter } from 'next/router';

export default function Home({ user }) {
  const router = useRouter();

  useEffect(() => {
    if (user) {
      router.replace('/dashboard');
    } else {
      router.replace('/login');
    }
  }, [user, router]);

  return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="loading-spinner w-8 h-8"></div>
      <span className="ml-3 text-gray-600">Redirecting...</span>
    </div>
  );
}