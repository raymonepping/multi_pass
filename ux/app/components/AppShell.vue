<script setup lang="ts">
const route = useRoute()
</script>

<template>
  <div class="app-grid">
    <aside class="sidebar">
      <NuxtLink to="/" class="brand" aria-label="Multipass control plane home">
        <span class="brand-mark" aria-hidden="true"><span /></span>
        <span>Multipass</span>
      </NuxtLink>

      <nav class="mt-10" aria-label="Primary navigation">
        <NuxtLink to="/" class="nav-link" :class="{ active: route.path === '/' || route.path.startsWith('/instances') }">
          <svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="5" width="16" height="14" rx="3"/><path d="M8 9h8M8 13h5"/></svg>
          Instances
        </NuxtLink>
      </nav>

      <div class="sidebar-foot">
        <span class="local-dot" />
        <div>
          <p>Local control plane</p>
          <span>127.0.0.1</span>
        </div>
      </div>
    </aside>

    <main class="main-column">
      <header class="topbar">
        <div class="mobile-brand">
          <span class="brand-mark" aria-hidden="true"><span /></span>
          <span>Multipass</span>
        </div>
        <div class="ml-auto flex items-center gap-3 text-xs text-[var(--muted)]">
          <span class="hidden sm:inline">Local environment</span>
          <span class="environment-chip"><span /> macOS</span>
        </div>
      </header>
      <div class="page-frame"><slot /></div>
    </main>
  </div>
</template>
