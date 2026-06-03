import React, { useState, useEffect, useRef } from 'react';
import { Trash2, ArrowDown } from 'lucide-react';
import { EventsOn, EventsOff } from '../../wailsjs/runtime/runtime';

interface LogLine {
  text: string;
  time: string;
}

const CATEGORIES = [
  { id: 'system', label: 'System' },
  { id: 'caddy', label: 'Caddy' },
  { id: 'mariadb', label: 'MariaDB' },
  { id: 'mailpit', label: 'Mailpit' },
  { id: 'php', label: 'PHP' },
  { id: 'runtime', label: 'Runtime (Node/Bun)' }
];

export default function TerminalLogs() {
  const [activeTab, setActiveTab] = useState('system');
  const [logs, setLogs] = useState<Record<string, LogLine[]>>({
    system: [],
    caddy: [],
    mariadb: [],
    mailpit: [],
    php: [],
    runtime: []
  });
  const [autoScroll, setAutoScroll] = useState(true);
  const logEndRef = useRef<HTMLDivElement | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);

  // 用於追蹤當前啟動的分頁，以避免在 handleIncomingLog 中閉包抓到舊值
  const activeTabRef = useRef(activeTab);
  // 用於防抖動 (debounce) 自動切換分頁的定時器
  const debounceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // 當 activeTab 改變時，更新 Ref 並清除任何懸而未決的自動切換定時器
  useEffect(() => {
    activeTabRef.current = activeTab;
    if (debounceTimerRef.current) {
      clearTimeout(debounceTimerRef.current);
      debounceTimerRef.current = null;
    }
  }, [activeTab]);

  // 元件卸載時清理定時器
  useEffect(() => {
    return () => {
      if (debounceTimerRef.current) {
        clearTimeout(debounceTimerRef.current);
      }
    };
  }, []);

  // 訂閱 Go 端的日誌 Event
  useEffect(() => {
    const handleIncomingLog = (data: any) => {
      if (!data || !data.category) return;
      const category = data.category === 'node' ? 'runtime' : data.category;
      
      const isValidCategory = category === 'system' || category === 'caddy' || category === 'mariadb' || category === 'mailpit' || category === 'php' || category === 'runtime';
      if (isValidCategory) {
        setLogs(prev => {
          const currentLogs = prev[category] || [];
          // 限制單個分頁最大日誌行數為 1000 行
          const newLogs = [...currentLogs, { text: data.message, time: data.time }];
          if (newLogs.length > 1000) {
            newLogs.shift();
          }
          return {
            ...prev,
            [category]: newLogs
          };
        });

        // 根據最新有 log 的分頁自動切換 (防抖動 500ms，做法參考舊 Fyne 的 terminal log 處理)
        if (category !== activeTabRef.current) {
          if (debounceTimerRef.current) {
            clearTimeout(debounceTimerRef.current);
          }
          debounceTimerRef.current = setTimeout(() => {
            if (category !== activeTabRef.current) {
              setActiveTab(category);
            }
          }, 500);
        }
      }
    };

    EventsOn('log', handleIncomingLog);

    return () => {
      EventsOff('log');
    };
  }, []);

  // 自動滾動到底部
  useEffect(() => {
    if (autoScroll && logEndRef.current) {
      logEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [logs, activeTab, autoScroll]);

  // 監聽使用者手動滾動，決定是否開啟自動滾動
  const handleScroll = () => {
    if (!containerRef.current) return;
    const { scrollTop, scrollHeight, clientHeight } = containerRef.current;
    // 如果距離底部小於 50px，視為啟用自動滾動
    const isAtBottom = scrollHeight - scrollTop - clientHeight < 50;
    setAutoScroll(isAtBottom);
  };

  const handleClearLogs = () => {
    setLogs(prev => ({
      ...prev,
      [activeTab]: []
    }));
  };

  // Warp 風格日誌著色
  const getLineColor = (text: string) => {
    const lower = text.toLowerCase();
    if (
      lower.includes('error') || 
      lower.includes('failed') || 
      lower.includes('🔴') || 
      lower.includes('❌') || 
      lower.includes('無法') || 
      lower.includes('失敗') || 
      lower.includes('missing') ||
      lower.includes('fatal')
    ) {
      return 'text-red-400 font-semibold';
    }
    if (
      lower.includes('warn') || 
      lower.includes('warning') || 
      lower.includes('⚠️') || 
      lower.includes('警示') ||
      lower.includes('deprecated')
    ) {
      return 'text-amber-400 font-semibold';
    }
    if (
      lower.includes('info') || 
      lower.includes('success') || 
      lower.includes('✅') || 
      lower.includes('運作中') || 
      lower.includes('運行中') || 
      lower.includes('已啟動') || 
      lower.includes('就緒') ||
      lower.includes('connected') ||
      lower.includes('started') ||
      lower.includes('listening')
    ) {
      return 'text-emerald-400 font-medium';
    }
    return 'text-gray-300';
  };

  return (
    <div className="flex flex-col h-full bg-[#08080a] overflow-hidden select-none">
      {/* 分頁 Tab 與控制項 */}
      <div className="flex justify-between items-center border-b border-darkBorder bg-[#0b0b0e] px-3 select-none">
        <div className="flex overflow-x-auto scrollbar-none">
          {CATEGORIES.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`px-4 py-2.5 text-[11px] font-bold border-b-2 transition duration-200 shrink-0 ${
                activeTab === tab.id
                  ? 'border-blue-500 text-blue-400 bg-white/[0.02]'
                  : 'border-transparent text-gray-400 hover:text-gray-200'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        <div className="flex gap-2 py-1.5 shrink-0">
          {!autoScroll && (
            <button
              onClick={() => {
                setAutoScroll(true);
                logEndRef.current?.scrollIntoView({ behavior: 'smooth' });
              }}
              className="px-2.5 py-1 text-[10px] border border-darkBorder rounded-lg bg-darkInput text-blue-400 hover:border-blue-500/50 flex items-center gap-1 transition font-bold"
            >
              <ArrowDown size={11} /> 自動滾動
            </button>
          )}
          <button
            onClick={handleClearLogs}
            className="px-2.5 py-1 text-[10px] border border-darkBorder rounded-lg bg-darkInput text-red-400 hover:border-red-500/50 flex items-center gap-1 transition font-bold"
          >
            <Trash2 size={11} /> 清空日誌
          </button>
        </div>
      </div>

      {/* 日誌內容展示區 */}
      <div
        ref={containerRef}
        onScroll={handleScroll}
        className="flex-1 p-5 overflow-y-auto font-mono text-[11px] leading-relaxed bg-[#060608] text-gray-300"
      >
        {logs[activeTab] && logs[activeTab].length > 0 ? (
          <div className="whitespace-pre-wrap break-all space-y-0.5">
            {logs[activeTab].map((line, idx) => (
              <div key={idx} className="hover:bg-white/[0.03] px-1 py-0.5 rounded transition duration-75">
                <span className="text-gray-600 select-none mr-2 font-semibold">[{line.time}]</span>
                <span className={getLineColor(line.text)}>{line.text}</span>
              </div>
            ))}
            <div ref={logEndRef} />
          </div>
        ) : (
          <div className="h-full flex items-center justify-center text-gray-600 select-none italic text-xs font-semibold">
            暫時沒有日誌輸出
          </div>
        )}
      </div>
    </div>
  );
}
