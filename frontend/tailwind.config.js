/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './pages/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          50: '#eff6ff',
          100: '#dbeafe',
          500: '#3b82f6',
          600: '#2563eb',
          700: '#1d4ed8',
        }
      },
      maxHeight: {
        '90vh': '90vh',
      },
      maxWidth: {
        'xs': '20rem',
        'md': '28rem',
        '7xl': '80rem',
      }
    },
  },
  plugins: [],
};