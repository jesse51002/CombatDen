import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';

import { App } from './App';
// Order matters: the token declarations must land before the sheets that read
// them. Every other stylesheet in the app is a CSS Module, imported by the
// component that owns it.
import './styles/tokens.css';
import './styles/base.css';

const host = document.getElementById('root');
if (!host) throw new Error('index.html is missing #root');

createRoot(host).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
