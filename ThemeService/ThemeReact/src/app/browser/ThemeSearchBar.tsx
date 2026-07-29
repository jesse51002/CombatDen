// Ports ../../../../../CRM/lib/features/members/presentation/widgets/
// member_app/theme_tab/theme_search_bar.dart.
//
// Search input over the theme list. Reports the RAW text on every change; the
// consuming pager owns the debounce (`StylesPager.setQuery`, already in
// theme-react). The clear chip appears only when the field has content.

import { useState } from 'react';

import { CloseIcon, SearchIcon } from '../widgets/icons';

import styles from './ThemeSearchBar.module.css';

export interface ThemeSearchBarProps {
  onChanged: (value: string) => void;
}

export function ThemeSearchBar({ onChanged }: ThemeSearchBarProps) {
  // Dart holds this in a `TextEditingController` and rebuilds on its notify;
  // a controlled input is the same thing with the controller built in.
  const [value, setValue] = useState('');

  const change = (next: string) => {
    setValue(next);
    onChanged(next);
  };

  return (
    <div className={styles.bar}>
      <SearchIcon className={styles.icon} size={20} />
      <input
        className={styles.input}
        type="search"
        value={value}
        placeholder="Search themes"
        aria-label="Search themes"
        onChange={(event) => change(event.target.value)}
      />
      {value !== '' && (
        <button type="button" className={styles.clear} aria-label="Clear search" onClick={() => change('')}>
          <CloseIcon size={20} />
        </button>
      )}
    </div>
  );
}
