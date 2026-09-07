import tailwindcss from '@tailwindcss/vite'

export default defineNuxtConfig({
  compatibilityDate: '2026-09-05',
  devtools: { enabled: true },
  modules: ['@nuxt/eslint'],
  css: ['~/assets/css/main.css'],
  vite: { plugins: [tailwindcss()] },
  typescript: { strict: true, typeCheck: true },
  runtimeConfig: {
    repositoryRoot: process.env.MULTIPASS_CONTROL_REPOSITORY_ROOT || '..',
    public: {
      refreshSeconds: 15,
    },
  },
  nitro: {
    routeRules: {
      '/api/**': { headers: { 'cache-control': 'no-store' } },
    },
  },
  app: {
    head: {
      title: 'Multipass Control Plane',
      meta: [
        { name: 'description', content: 'Local infrastructure posture and control for the Vault Multipass lab.' },
        { name: 'theme-color', content: '#0b0d10' },
      ],
    },
  },
})
