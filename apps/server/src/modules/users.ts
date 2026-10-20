import { z } from "zod";
import argon2 from "argon2";
import { db } from "../services/db";
import { publicUser } from "../services/messages";
import { requireCondition } from "../security/errors";
import { uuid } from "../../../../packages/contracts";
export async function usersRoute(
  userId: string,
  method: string,
  path: string[],
  body: unknown,
  url: URL,
) {
  const [, id, sub] = path;
  if (id === "search" && method === "GET") {
    const q = z.string().min(4).max(24).parse(url.searchParams.get("q"));
    return db.user.findMany({
      where: { qchatId: q.toLowerCase(), disabled: false },
      select: publicUser,
      take: 10,
    });
  }
  if (id === "me") {
    if (sub === "password" && method === "POST") {
      const v = z
        .object({
          currentPassword: z.string().max(128),
          password: z.string().min(12).max(128),
        })
        .strict()
        .parse(body);
      const u = await db.user.findUniqueOrThrow({ where: { id: userId } });
      requireCondition(
        await argon2.verify(u.passwordHash, v.currentPassword),
        401,
        "INVALID_CREDENTIALS",
      );
      await db.$transaction([
        db.user.update({
          where: { id: userId },
          data: {
            passwordHash: await argon2.hash(v.password, {
              type: argon2.argon2id,
            }),
          },
        }),
        db.userSession.updateMany({
          where: { userId },
          data: { revokedAt: new Date() },
        }),
      ]);
      return { ok: true };
    }
    if (sub === "avatar" && method === "POST") {
      const { mediaId } = z.object({ mediaId: uuid }).strict().parse(body);
      requireCondition(
        await db.media.findFirst({
          where: {
            id: mediaId,
            ownerId: userId,
            status: "READY",
            mime: { startsWith: "image/" },
          },
        }),
      );
      return db.user.update({
        where: { id: userId },
        data: { avatarId: mediaId },
        select: publicUser,
      });
    }
    if (sub === "export" && method === "GET") {
      return {
        profile: await db.user.findUnique({
          where: { id: userId },
          select: { ...publicUser, email: true, createdAt: true, gender: true, region: true, phone: true, poke: true },
        }),
        messages: await db.message.findMany({
          where: { senderId: userId },
          take: 1000,
        }),
        moments: await db.moment.findMany({
          where: { authorId: userId },
          take: 1000,
        }),
      };
    }
    if (!sub && method === "GET")
      return db.user.findUnique({
        where: { id: userId },
        select: {
          ...publicUser,
          email: true,
          emailVerified: true,
          allowRequests: true,
          previewPush: true,
          gender: true,
          region: true,
          phone: true,
          poke: true,
        },
      });
    if (!sub && method === "PATCH") {
      const data = z
        .object({
          nickname: z.string().trim().min(1).max(64).optional(),
          bio: z.string().max(300).optional(),
          gender: z.enum(["", "male", "female", "other"]).optional(),
          region: z.string().trim().max(100).optional(),
          phone: z.string().trim().max(30).regex(/^[+\d ()-]*$/).optional(),
          poke: z.string().trim().max(100).optional(),
          allowRequests: z.boolean().optional(),
          previewPush: z.boolean().optional(),
        })
        .strict()
        .parse(body);
      return db.user.update({
        where: { id: userId },
        data,
        select: publicUser,
      });
    }
    if (!sub && method === "DELETE") {
      const { password } = z
        .object({ password: z.string().max(128) })
        .strict()
        .parse(body);
      const u = await db.user.findUniqueOrThrow({ where: { id: userId } });
      requireCondition(
        await argon2.verify(u.passwordHash, password),
        401,
        "INVALID_CREDENTIALS",
      );
      await db.$transaction([
        db.user.update({
          where: { id: userId },
          data: {
            disabled: true,
            nickname: "Deleted account",
            bio: "",
            avatarId: null,
          },
        }),
        db.userSession.updateMany({
          where: { userId },
          data: { revokedAt: new Date() },
        }),
      ]);
      return { ok: true };
    }
  }
  if (id && method === "GET")
    return db.user.findUnique({
      where: { id: uuid.parse(id) },
      select: publicUser,
    });
}
