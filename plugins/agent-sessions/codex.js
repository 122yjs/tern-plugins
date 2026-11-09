'use strict';

// Codex stores both conversation messages and tool/protocol records in a rollout.
function message(record) {
  if (!record || record.type !== 'response_item' || !record.payload) return null;
  const item = record.payload;
  if (item.type !== 'message' || (item.role !== 'user' && item.role !== 'assistant')) return null;
  const text = (Array.isArray(item.content) ? item.content : [])
    .filter(part => part && (part.type === 'input_text' || part.type === 'output_text') && typeof part.text === 'string')
    .map(part => part.text).join('\n\n').trim();
  if (!text || (item.role === 'user' && /^\s*<(?:environment_context|user_instructions|permissions instructions|collaboration_mode)(?:\s|>)/i.test(text))) return null;
  return { role: item.role, text };
}

module.exports = { message };
