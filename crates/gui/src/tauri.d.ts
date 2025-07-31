// Type definitions for Tauri v2
declare global {
  interface Window {
    __TAURI__: {
      core: {
        invoke: <T = any>(command: string, args?: any) => Promise<T>;
      };
      event: {
        listen: (event: string, handler: (event: any) => void) => Promise<() => void>;
      };
      window: {
        WebviewWindow: any; // We'll type this properly later
      };
    };
  }
}

export {};
