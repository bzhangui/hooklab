// Public, deterministic teaching fixtures. This module never calls a HookLab API.
export const scenarios = Object.freeze([
  {
    id: 'happy', role: '发布方', title: '订单创建，正常送达',
    description: '发布方带幂等键提交订单事件；HookLab 验证契约并将一次签名投递送达消费者。',
    outcome: 'delivered', attempts: 1, accepted: 1, businessEffects: 1,
    steps: [
      ['发布', '接收 order.created 和幂等键；数据均为合成样例。'],
      ['校验', '契约校验通过，事件与交付任务在事务中保存。'],
      ['投递', 'Worker 签名后发送，消费者验签并返回 204。'],
      ['结果', '交付成功，业务效果记录一次。'],
    ],
  },
  {
    id: 'retry', role: '接收方', title: '暂时故障，安全重试',
    description: '接收端第一次返回 503；第二次使用同一交付 ID 重试，消费者按 ID 去重。',
    outcome: 'delivered', attempts: 2, accepted: 1, businessEffects: 1,
    steps: [
      ['发布', '有效事件入库，创建交付任务。'],
      ['首次尝试', '消费者暂时不可用，返回 503；尝试历史保留。'],
      ['重试', '根据重试计划再次发送，同一交付 ID、重新签名。'],
      ['结果', '消费者验签并去重，返回 204；业务效果仅一次。'],
    ],
  },
  {
    id: 'forged', role: '安全员', title: '伪造签名，被拒绝',
    description: '第三方回调的签名与原始正文不匹配；认证失败后不入库、不创建投递。',
    outcome: 'rejected', attempts: 0, accepted: 0, businessEffects: 0,
    steps: [
      ['接入', '收到声称来自提供方的合成回调。'],
      ['验签', '按原始正文核对签名，发现不匹配。'],
      ['拒绝', '返回未授权；不继续解析、路由或持久化。'],
      ['结果', '没有交付任务，也没有业务副作用。'],
    ],
  },
  {
    id: 'contract', role: '开发者', title: '契约不符，原子拒绝',
    description: '事件缺少必填字段；在产生事件和交付任务前返回校验错误。',
    outcome: 'rejected', attempts: 0, accepted: 0, businessEffects: 0,
    steps: [
      ['发布', '提交缺少 orderId 的合成订单。'],
      ['校验', '事件不满足已发布的版本化契约。'],
      ['拒绝', '返回 422；不保存半成品事件或投递任务。'],
      ['结果', '开发者可修正请求后重试。'],
    ],
  },
  {
    id: 'dead', role: '运维员', title: '持续失败，进入死信',
    description: '消费者持续返回不可恢复错误；投递停止自动重试，留待授权人员调查。',
    outcome: 'dead_lettered', attempts: 1, accepted: 1, businessEffects: 0,
    steps: [
      ['发布', '有效事件已持久化。'],
      ['尝试', '目标返回 400，记录脱敏诊断与尝试结果。'],
      ['死信', '停止自动投递，避免无界重试。'],
      ['处理', '运维员先修复接收端，再决定是否人工重试。'],
    ],
  },
  {
    id: 'tenant', role: '租户管理员', title: '跨租户访问，被阻止',
    description: '租户 A 的管理令牌尝试查看租户 B 资源；请求被拒绝，不返回 B 的数据。',
    outcome: 'rejected', attempts: 0, accepted: 0, businessEffects: 0,
    steps: [
      ['请求', '使用租户 A 的合成令牌查询租户 B。'],
      ['鉴权', '令牌哈希与目标租户不匹配。'],
      ['拒绝', '返回 401，未读取或更改租户 B 资源。'],
      ['结果', '管理界面不会显示其他租户的事件正文或密钥。'],
    ],
  },
]);

export function getScenario(id) {
  return scenarios.find(item => item.id === id) ?? null;
}
