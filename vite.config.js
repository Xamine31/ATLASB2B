import {defineConfig} from 'vite';
import react from '@vitejs/plugin-react';
const repo = process.env.GITHUB_REPOSITORY?.split('/')[1];
if (process.env.GITHUB_PAGES === 'true' && !repo) throw Error('GITHUB_REPOSITORY absent : impossible de calculer la base GitHub Pages');
export default defineConfig({
  plugins: [react()],
  base: process.env.GITHUB_PAGES === 'true' ? `/${repo}/` : '/',
  build: {outDir:'dist',emptyOutDir:true}
});
