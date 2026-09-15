import { z } from 'zod';

// ==========================================
// Inbound Messages (Device -> Server)
// ==========================================

export const RegisterMessageSchema = z.object({
  type: z.literal('register'),
  role: z.enum(['host', 'controller']),
  deviceId: z.string().min(1),
  deviceName: z.string().min(1),
});

export const CreatePairingCodeMessageSchema = z.object({
  type: z.literal('create_pairing_code'),
});

export const PairMessageSchema = z.object({
  type: z.literal('pair'),
  code: z.string().min(1),
  deviceId: z.string().min(1),
  deviceName: z.string().min(1),
});

export const ApprovePairMessageSchema = z.object({
  type: z.literal('approve_pair'),
  peerDeviceId: z.string().min(1),
});

export const DenyPairMessageSchema = z.object({
  type: z.literal('deny_pair'),
  peerDeviceId: z.string().min(1),
});

export const ResumeSessionMessageSchema = z.object({
  type: z.literal('resume_session'),
  authToken: z.string().min(1),
  peerDeviceId: z.string().min(1),
});

export const OfferMessageSchema = z.object({
  type: z.literal('offer'),
  targetDeviceId: z.string().min(1),
  sdp: z.string().min(1),
});

export const AnswerMessageSchema = z.object({
  type: z.literal('answer'),
  targetDeviceId: z.string().min(1),
  sdp: z.string().min(1),
});

export const IceCandidateObjectSchema = z.object({
  candidate: z.string(),
  sdpMid: z.string().nullable().optional(),
  sdpMLineIndex: z.number().nullable().optional(),
  usernameFragment: z.string().nullable().optional(),
}).passthrough();

export const IceCandidateMessageSchema = z.object({
  type: z.literal('ice_candidate'),
  targetDeviceId: z.string().min(1),
  candidate: IceCandidateObjectSchema,
});

export const EndSessionMessageSchema = z.object({
  type: z.literal('end_session'),
  targetDeviceId: z.string().min(1),
});

export const RequestTurnCredentialsMessageSchema = z.object({
  type: z.literal('request_turn_credentials'),
});

export const AppListMessageSchema = z.object({
  type: z.literal('app_list'),
  targetDeviceId: z.string().optional(),
  apps: z.array(z.record(z.unknown())),
}).passthrough();

export const SelectWindowMessageSchema = z.object({
  type: z.literal('select_window'),
  targetDeviceId: z.string().optional(),
  windowId: z.number(),
}).passthrough();

export const InboundMessageSchema = z.discriminatedUnion('type', [
  RegisterMessageSchema,
  CreatePairingCodeMessageSchema,
  PairMessageSchema,
  ApprovePairMessageSchema,
  DenyPairMessageSchema,
  ResumeSessionMessageSchema,
  OfferMessageSchema,
  AnswerMessageSchema,
  IceCandidateMessageSchema,
  EndSessionMessageSchema,
  RequestTurnCredentialsMessageSchema,
  AppListMessageSchema,
  SelectWindowMessageSchema,
]);

export type RegisterMessage = z.infer<typeof RegisterMessageSchema>;
export type CreatePairingCodeMessage = z.infer<typeof CreatePairingCodeMessageSchema>;
export type PairMessage = z.infer<typeof PairMessageSchema>;
export type ApprovePairMessage = z.infer<typeof ApprovePairMessageSchema>;
export type DenyPairMessage = z.infer<typeof DenyPairMessageSchema>;
export type ResumeSessionMessage = z.infer<typeof ResumeSessionMessageSchema>;
export type OfferMessage = z.infer<typeof OfferMessageSchema>;
export type AnswerMessage = z.infer<typeof AnswerMessageSchema>;
export type IceCandidateMessage = z.infer<typeof IceCandidateMessageSchema>;
export type EndSessionMessage = z.infer<typeof EndSessionMessageSchema>;
export type RequestTurnCredentialsMessage = z.infer<typeof RequestTurnCredentialsMessageSchema>;
export type AppListMessage = z.infer<typeof AppListMessageSchema>;
export type SelectWindowMessage = z.infer<typeof SelectWindowMessageSchema>;

export type InboundMessage = z.infer<typeof InboundMessageSchema>;

// ==========================================
// Outbound Messages (Server -> Device)
// ==========================================

export type ErrorCode =
  | 'INVALID_CODE'
  | 'CODE_EXPIRED'
  | 'NOT_PAIRED'
  | 'PEER_OFFLINE'
  | 'BAD_TOKEN'
  | 'INVALID_MESSAGE'
  | 'ALREADY_REGISTERED'
  | 'UNREGISTERED'
  | 'UNAUTHORIZED';

export interface RegisteredMessage {
  type: 'registered';
  deviceId: string;
}

export interface PairingCodeMessage {
  type: 'pairing_code';
  code: string;
  expiresInSec: number;
}

export interface PairRequestMessage {
  type: 'pair_request';
  fromDeviceId: string;
  fromDeviceName: string;
}

export interface PairedMessage {
  type: 'paired';
  peerDeviceId: string;
  peerDeviceName: string;
  authToken: string;
}

export interface PairDeniedMessage {
  type: 'pair_denied';
}

export interface PairExpiredMessage {
  type: 'pair_expired';
}

export interface RelayOfferMessage {
  type: 'offer';
  fromDeviceId: string;
  sdp: string;
}

export interface RelayAnswerMessage {
  type: 'answer';
  fromDeviceId: string;
  sdp: string;
}

export interface RelayIceCandidateMessage {
  type: 'ice_candidate';
  fromDeviceId: string;
  candidate: Record<string, unknown>;
}

export interface PeerDisconnectedMessage {
  type: 'peer_disconnected';
  peerDeviceId: string;
}

export interface TurnCredentialsMessage {
  type: 'turn_credentials';
  urls: string[];
  username: string;
  credential: string;
  ttlSec: number;
}

export interface ErrorMessage {
  type: 'error';
  code: ErrorCode;
  message: string;
}

export interface GenericRelayMessage {
  type: string;
  fromDeviceId?: string;
  [key: string]: unknown;
}

export type OutboundMessage =
  | RegisteredMessage
  | PairingCodeMessage
  | PairRequestMessage
  | PairedMessage
  | PairDeniedMessage
  | PairExpiredMessage
  | RelayOfferMessage
  | RelayAnswerMessage
  | RelayIceCandidateMessage
  | PeerDisconnectedMessage
  | TurnCredentialsMessage
  | ErrorMessage
  | GenericRelayMessage;
